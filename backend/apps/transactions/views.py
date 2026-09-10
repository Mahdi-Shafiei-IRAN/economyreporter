from datetime import datetime, time
from datetime import timezone as dt_timezone

from django.db import IntegrityError, transaction as db_transaction
from django.db.models import Sum
from django.db.models.functions import Coalesce
from django.utils import timezone as dj_timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework import viewsets
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import BankAccount, Card
from apps.categories.models import Category
from apps.common.family import resolve_family, user_family_ids

from .models import Transaction
from .serializers import TransactionSerializer


def _validate_refs(family, account, card, category):
    """اطمینان از اینکه حساب/کارت/دسته‌ی ارجاع‌شده به همین خانواده تعلق دارند."""
    if account is not None and account.family_id != family.id:
        raise ValidationError({"account": "حساب متعلق به این خانواده نیست"})
    if card is not None and card.account.family_id != family.id:
        raise ValidationError({"card": "کارت متعلق به این خانواده نیست"})
    if category is not None and category.family_id != family.id:
        raise ValidationError({"category": "دسته متعلق به این خانواده نیست"})


class TransactionViewSet(viewsets.ModelViewSet):
    serializer_class = TransactionSerializer

    def get_queryset(self):
        qs = Transaction.objects.filter(
            family_id__in=user_family_ids(self.request.user)
        ).order_by("-server_received_at")

        params = self.request.query_params
        if v := params.get("kind"):
            qs = qs.filter(kind=v)
        if v := params.get("category"):
            qs = qs.filter(category_id=v)
        if v := params.get("account"):
            qs = qs.filter(account_id=v)
        if v := params.get("card"):
            qs = qs.filter(card_id=v)
        if v := params.get("member"):
            qs = qs.filter(owner_id=v)
        if v := params.get("needs_review"):
            qs = qs.filter(needs_review=v.lower() in ("1", "true", "yes"))
        return qs

    def perform_create(self, serializer):
        family = resolve_family(self.request.user, self.request.data.get("family"))
        data = serializer.validated_data
        _validate_refs(family, data.get("account"), data.get("card"), data.get("category"))
        serializer.save(family=family, owner=self.request.user)


class SyncView(APIView):
    """آپلود دسته‌ای و idempotent تراکنش‌ها از دستگاه."""

    def post(self, request):
        family = resolve_family(request.user, request.data.get("family"))
        items = request.data.get("transactions")
        if not isinstance(items, list):
            raise ValidationError({"transactions": "باید یک لیست باشد"})
        device_id = request.data.get("device_id", "")

        valid_accounts = set(
            BankAccount.objects.filter(family=family).values_list("id", flat=True)
        )
        valid_cards = set(
            Card.objects.filter(account__family=family).values_list("id", flat=True)
        )
        valid_categories = set(
            Category.objects.filter(family=family).values_list("id", flat=True)
        )

        results = [
            self._process_item(
                item, family, request.user, device_id,
                valid_accounts, valid_cards, valid_categories,
            )
            for item in items
        ]
        return Response({"success": True, "results": results})

    def _process_item(
        self, item, family, user, device_id, valid_accounts, valid_cards, valid_categories
    ):
        tid = item.get("id")

        # ۱) idempotency بر اساس id
        if tid:
            existing = Transaction.objects.filter(id=tid).first()
            if existing:
                if existing.family_id == family.id:
                    return {"id": str(tid), "status": "already_exists"}
                return {"id": str(tid), "status": "error", "detail": "تعارض شناسه"}

        # ۲) ضدتکرار بر اساس اثرانگشت پیامک
        h = (item.get("source_message_hash") or "").strip()
        if h:
            dup = Transaction.objects.filter(family=family, source_message_hash=h).first()
            if dup:
                return {"id": str(dup.id), "status": "already_exists"}

        serializer = TransactionSerializer(data=item)
        if not serializer.is_valid():
            return {"id": str(tid) if tid else None, "status": "error", "detail": serializer.errors}

        data = serializer.validated_data
        acc, card, cat = data.get("account"), data.get("card"), data.get("category")
        if acc is not None and acc.id not in valid_accounts:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "حساب نامعتبر"}
        if card is not None and card.id not in valid_cards:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "کارت نامعتبر"}
        if cat is not None and cat.id not in valid_categories:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "دسته نامعتبر"}

        try:
            with db_transaction.atomic():
                obj = serializer.save(
                    family=family,
                    owner=user,
                    device_id=data.get("device_id") or device_id,
                )
            return {"id": str(obj.id), "status": "created"}
        except IntegrityError:
            # رقابت هم‌زمان روی اثرانگشت یکتا
            return {"id": str(tid) if tid else None, "status": "already_exists"}


class DashboardSummaryView(APIView):
    """جمع درآمد/هزینه/مانده به‌تفکیک عضو/دسته/کارت. مبالغ به ریال."""

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        frm = _parse_dt(request.query_params.get("from"), end=False)
        to = _parse_dt(request.query_params.get("to"), end=True)

        qs = Transaction.objects.filter(
            family=family, amount_rial__isnull=False
        ).annotate(effective_date=Coalesce("transaction_date", "server_received_at"))
        if frm:
            qs = qs.filter(effective_date__gte=frm)
        if to:
            qs = qs.filter(effective_date__lte=to)

        def total(kind):
            return qs.filter(kind=kind).aggregate(s=Sum("amount_rial"))["s"] or 0

        income = total(Transaction.Kind.INCOME)
        expense = total(Transaction.Kind.EXPENSE)

        expenses = qs.filter(kind=Transaction.Kind.EXPENSE)
        members = [
            {
                "id": str(row["owner"]),
                "name": row["owner__full_name"] or row["owner__email"],
                "expenses": row["amount"] or 0,
            }
            for row in expenses.values("owner", "owner__full_name", "owner__email")
            .annotate(amount=Sum("amount_rial"))
            .order_by("-amount")
        ]
        categories = [
            {
                "category": str(row["category"]) if row["category"] else None,
                "name": row["category__name"],
                "amount": row["amount"] or 0,
            }
            for row in expenses.values("category", "category__name")
            .annotate(amount=Sum("amount_rial"))
            .order_by("-amount")
        ]
        cards = [
            {
                "card": str(row["card"]) if row["card"] else None,
                "card_last4": row["card__card_last4"],
                "amount": row["amount"] or 0,
            }
            for row in expenses.values("card", "card__card_last4")
            .annotate(amount=Sum("amount_rial"))
            .order_by("-amount")
        ]

        return Response(
            {
                "period": {
                    "from": frm.isoformat() if frm else None,
                    "to": to.isoformat() if to else None,
                },
                "family": {
                    "income": income,
                    "expenses": expense,
                    "balance": income - expense,
                },
                "members": members,
                "categories": categories,
                "cards": cards,
            }
        )


def _parse_dt(value, end=False):
    if not value:
        return None
    dt = parse_datetime(value)
    if dt is None:
        d = parse_date(value)
        if d is None:
            return None
        dt = datetime.combine(d, time.max if end else time.min)
    if dj_timezone.is_naive(dt):
        dt = dj_timezone.make_aware(dt, dt_timezone.utc)
    return dt
