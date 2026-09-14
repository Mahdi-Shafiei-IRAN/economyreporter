import uuid
from collections import defaultdict
from datetime import datetime, time
from datetime import timezone as dt_timezone

from django.db import IntegrityError, transaction as db_transaction
from django.db.models import Q, Sum
from django.db.models.functions import Coalesce
from django.utils import timezone as dj_timezone
from django.utils.dateparse import parse_date, parse_datetime
from rest_framework import viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import BankAccount, Card
from apps.categories.models import Category
from apps.common.family import (
    is_family_manager,
    resolve_family,
    role_scoped_q,
    user_family_ids,
)

from .models import Transaction
from .serializers import TransactionSerializer

# فقط صاحب تراکنش (عضوی که کارت مال اوست) این‌ها را تغییر می‌دهد.
CONTENT_FIELDS = frozenset(
    {
        "kind",
        "amount_rial",
        "balance_after_rial",
        "raw_amount",
        "raw_unit",
        "counterparty",
        "description",
        "allocations",
        "is_deleted",
        "needs_review",
        "transaction_date",
    }
)
# «کارت مال کیست» را گوشیِ دریافت‌کننده‌ی پیامک تعیین می‌کند.
ATTRIBUTION_FIELDS = frozenset({"person_name", "wallet_label", "bank_id", "card_last4"})

PULL_DEFAULT_LIMIT = 500
PULL_MAX_LIMIT = 1000


def _validate_refs(family, account, card, category):
    """اطمینان از اینکه حساب/کارت/دسته‌ی ارجاع‌شده به همین خانواده تعلق دارند."""
    if account is not None and account.family_id != family.id:
        raise ValidationError({"account": "حساب متعلق به این خانواده نیست"})
    if card is not None and card.account.family_id != family.id:
        raise ValidationError({"card": "کارت متعلق به این خانواده نیست"})
    if category is not None and category.family_id != family.id:
        raise ValidationError({"category": "دسته متعلق به این خانواده نیست"})


def _family_members(family):
    """نگاشت شناسه‌ی کاربر → کاربر، برای اعضای یک خانواده."""
    return {
        str(m.user_id): m.user for m in family.memberships.select_related("user")
    }


def _resolve_owner(owner_member, members, fallback):
    """صاحب تراکنش: عضوِ اعلام‌شده (اگر عضو خانواده باشد)، وگرنه fallback."""
    if owner_member and str(owner_member) in members:
        return members[str(owner_member)]
    return fallback


def _iso_z(dt):
    return dt.astimezone(dt_timezone.utc).isoformat().replace("+00:00", "Z")


class TransactionViewSet(viewsets.ModelViewSet):
    serializer_class = TransactionSerializer

    def get_queryset(self):
        qs = (
            Transaction.objects.filter(
                family_id__in=user_family_ids(self.request.user), is_deleted=False
            )
            # نقش: عضو عادی فقط مالِ خودش؛ مدیر خانواده و ادمین کل همه‌ی خانواده.
            .filter(role_scoped_q(self.request.user))
            .select_related("owner")
            .order_by("-server_received_at")
        )

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
        serializer.save(family=family, owner=self.request.user, captured_by=self.request.user)

    def _ensure_owner(self, obj):
        if obj.owner_id != self.request.user.id:
            raise PermissionDenied("فقط صاحب کارت می‌تواند این تراکنش را ویرایش کند")

    def perform_update(self, serializer):
        self._ensure_owner(serializer.instance)
        serializer.save()

    def perform_destroy(self, instance):
        # حذف نرم تا به گوشی‌های دیگر هم برسد.
        self._ensure_owner(instance)
        instance.is_deleted = True
        instance.save(update_fields=["is_deleted", "updated_at"])


def _cursor_of(tx):
    """«زمان|شناسه»، تا ردیف‌های با updated_at برابر (مثلاً یک عملیات گروهی در پنل)
    در مرز صفحه جا نیفتند."""
    return f"{_iso_z(tx.updated_at)}|{tx.id}"


def _after_cursor(qs, cursor):
    """ردیف‌های بعد از cursor به ترتیب (updated_at, id). cursor قدیمیِ فقط‌زمان هم پذیرفته می‌شود."""
    if not cursor:
        return qs
    stamp, _, last_id = str(cursor).partition("|")
    since = _parse_dt(stamp)
    if since is None:
        return qs
    try:
        last_id = uuid.UUID(last_id) if last_id else None
    except ValueError:
        last_id = None
    if last_id is None:
        return qs.filter(updated_at__gt=since)
    return qs.filter(Q(updated_at__gt=since) | Q(updated_at=since, id__gt=last_id))


class SyncView(APIView):
    """
    POST: آپلود دسته‌ای و idempotent تراکنش‌ها از دستگاه (ساخت یا به‌روزرسانی).
    GET: دریافت تغییرات خانواده از یک cursor به بعد (تا گوشی‌های دیگر هم ببینند).
    """

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        since = request.query_params.get("since") or None
        try:
            limit = int(request.query_params.get("limit", PULL_DEFAULT_LIMIT))
        except ValueError:
            limit = PULL_DEFAULT_LIMIT
        limit = max(1, min(limit, PULL_MAX_LIMIT))

        base = Transaction.objects.filter(family=family)
        # عضو عادی فقط تراکنش‌های خودش را دریافت می‌کند؛ مدیر/ادمین کلِ خانواده را.
        if not is_family_manager(request.user, family):
            base = base.filter(Q(owner=request.user) | Q(captured_by=request.user))
        qs = _after_cursor(
            base.select_related("owner").order_by("updated_at", "id"),
            since,
        )
        rows = list(qs[: limit + 1])
        has_more = len(rows) > limit
        rows = rows[:limit]

        # بدون تغییر تازه، همان cursor قبلی برمی‌گردد.
        cursor = _cursor_of(rows[-1]) if rows else since
        return Response(
            {
                "results": TransactionSerializer(rows, many=True).data,
                "cursor": cursor,
                "has_more": has_more,
            }
        )

    def post(self, request):
        family = resolve_family(request.user, request.data.get("family"))
        items = request.data.get("transactions")
        if not isinstance(items, list):
            raise ValidationError({"transactions": "باید یک لیست باشد"})
        device_id = request.data.get("device_id", "")

        ctx = {
            "family": family,
            "user": request.user,
            "device_id": device_id,
            "members": _family_members(family),
            "accounts": set(
                BankAccount.objects.filter(family=family).values_list("id", flat=True)
            ),
            "cards": set(
                Card.objects.filter(account__family=family).values_list("id", flat=True)
            ),
            "categories": set(
                Category.objects.filter(family=family).values_list("id", flat=True)
            ),
        }
        results = [self._process_item(item, ctx) for item in items]
        return Response({"success": True, "results": results})

    def _process_item(self, item, ctx):
        if not isinstance(item, dict):
            return {"id": None, "status": "error", "detail": "آیتم نامعتبر"}
        family, user = ctx["family"], ctx["user"]
        tid = item.get("id")

        # ۱) idempotency بر اساس id (و به‌روزرسانی اگر نسخه‌ی دستگاه جدیدتر باشد)
        if tid:
            existing = Transaction.objects.filter(id=tid).first()
            if existing:
                if existing.family_id != family.id:
                    return {"id": str(tid), "status": "error", "detail": "تعارض شناسه"}
                return self._update_existing(existing, item, ctx)

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
        if acc is not None and acc.id not in ctx["accounts"]:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "حساب نامعتبر"}
        if card is not None and card.id not in ctx["cards"]:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "کارت نامعتبر"}
        if cat is not None and cat.id not in ctx["categories"]:
            return {"id": str(tid) if tid else None, "status": "error", "detail": "دسته نامعتبر"}

        owner = _resolve_owner(item.get("owner_member"), ctx["members"], user)
        try:
            with db_transaction.atomic():
                obj = serializer.save(
                    family=family,
                    owner=owner,
                    captured_by=user,
                    device_id=data.get("device_id") or ctx["device_id"],
                )
            return {"id": str(obj.id), "status": "created"}
        except IntegrityError:
            # رقابت هم‌زمان روی اثرانگشت یکتا
            return {"id": str(tid) if tid else None, "status": "already_exists"}

    def _update_existing(self, existing, item, ctx):
        """
        «آخرین ویرایش برنده است» بر اساس client_updated_at.
        صاحب تراکنش محتوا را عوض می‌کند؛ گوشیِ دریافت‌کننده فقط انتساب (کارت مال کیست) را.
        """
        user = ctx["user"]
        tid = str(existing.id)
        incoming = _parse_dt(item.get("client_updated_at"))
        if incoming is None or (
            existing.client_updated_at is not None and incoming <= existing.client_updated_at
        ):
            return {"id": tid, "status": "already_exists"}

        is_owner = existing.owner_id == user.id
        is_capturer = existing.captured_by_id == user.id
        if not (is_owner or is_capturer):
            return {
                "id": tid,
                "status": "forbidden",
                "detail": "فقط صاحب کارت می‌تواند این تراکنش را ویرایش کند",
            }

        serializer = TransactionSerializer(existing, data=item, partial=True)
        if not serializer.is_valid():
            return {"id": tid, "status": "error", "detail": serializer.errors}

        allowed = set()
        if is_owner:
            allowed |= CONTENT_FIELDS
        if is_capturer:
            allowed |= ATTRIBUTION_FIELDS
        for field, value in serializer.validated_data.items():
            if field in allowed:
                setattr(existing, field, value)
        if is_capturer and "owner_member" in item:
            existing.owner = _resolve_owner(item.get("owner_member"), ctx["members"], user)
        existing.client_updated_at = incoming
        existing.save()
        return {"id": tid, "status": "updated"}


class DashboardSummaryView(APIView):
    """جمع درآمد/هزینه/مانده به‌تفکیک شخص/دسته/کارت. مبالغ به ریال."""

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        frm = _parse_dt(request.query_params.get("from"), end=False)
        to = _parse_dt(request.query_params.get("to"), end=True)

        qs = Transaction.objects.filter(
            family=family, amount_rial__isnull=False, is_deleted=False
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
                "name": row["person_name"] or row["owner__full_name"] or row["owner__phone"],
                "expenses": row["amount"] or 0,
            }
            for row in expenses.values(
                "owner", "person_name", "owner__full_name", "owner__phone"
            )
            .annotate(amount=Sum("amount_rial"))
            .order_by("-amount")
        ]

        # دسته‌ها از تخصیص‌های چندتایی (و برای داده‌ی قدیمی از FK دسته).
        by_category = defaultdict(int)
        for tx in expenses.select_related("category").only(
            "amount_rial", "allocations", "category__name"
        ):
            if tx.allocations:
                for a in tx.allocations:
                    by_category[a.get("name")] += int(a.get("amount_rial") or 0)
            else:
                by_category[tx.category.name if tx.category else None] += tx.amount_rial
        categories = [
            {"category": name, "name": name, "amount": amount}
            for name, amount in sorted(by_category.items(), key=lambda kv: -kv[1])
        ]

        cards = [
            {
                "card": None,
                "card_last4": row["card_last4"] or None,
                "amount": row["amount"] or 0,
            }
            for row in expenses.values("card_last4")
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
    value = str(value)
    dt = parse_datetime(value)
    if dt is None:
        d = parse_date(value)
        if d is None:
            return None
        dt = datetime.combine(d, time.max if end else time.min)
    if dj_timezone.is_naive(dt):
        dt = dj_timezone.make_aware(dt, dt_timezone.utc)
    return dt
