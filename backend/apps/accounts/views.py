import uuid

from django.db.models import Q
from django.utils.dateparse import parse_datetime
from rest_framework import viewsets
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.family import (
    is_family_manager,
    resolve_family,
    user_family_ids,
)
from apps.common.sync import upsert_each
from apps.families.models import FamilyMembership

from .models import BankAccount, Card, Wallet
from .serializers import BankAccountSerializer, CardSerializer, WalletSerializer


class BankAccountViewSet(viewsets.ModelViewSet):
    serializer_class = BankAccountSerializer

    def get_queryset(self):
        return BankAccount.objects.filter(
            family_id__in=user_family_ids(self.request.user)
        ).order_by("created_at")

    def perform_create(self, serializer):
        family_id = self.request.data.get("family")
        family = resolve_family(self.request.user, family_id)
        serializer.save(family=family, owner=self.request.user)


class CardViewSet(viewsets.ModelViewSet):
    serializer_class = CardSerializer

    def get_queryset(self):
        return Card.objects.filter(
            account__family_id__in=user_family_ids(self.request.user)
        ).order_by("created_at")

    def perform_create(self, serializer):
        account = serializer.validated_data["account"]
        if account.family_id not in user_family_ids(self.request.user):
            raise NotFound()  # نمی‌توان به حسابی که نمی‌بینی کارت وصل کرد
        serializer.save()


# --- هم‌گام‌سازی کیف‌ها (کارت/حساب اعضا) -------------------------------------

WALLET_PULL_LIMIT = 500


def _cursor_of(w):
    return f"{w.updated_at.isoformat()}|{w.id}"


def _after_cursor(qs, cursor):
    if not cursor:
        return qs
    stamp, _, last_id = cursor.partition("|")
    since = parse_datetime(stamp)
    if since is None:
        return qs
    try:
        last_id = uuid.UUID(last_id) if last_id else None
    except ValueError:
        last_id = None
    if last_id is None:
        return qs.filter(updated_at__gt=since)
    return qs.filter(Q(updated_at__gt=since) | Q(updated_at=since, id__gt=last_id))


class WalletSyncView(APIView):
    """
    GET: کیف‌های خانواده از یک cursor به بعد (عضو فقط مالِ خودش را می‌بیند).
    POST: آپلود دسته‌ای و idempotent کیف‌ها (ساخت یا به‌روزرسانی با شناسه‌ی گوشی).
    """

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        cursor = request.query_params.get("since") or None

        base = Wallet.objects.filter(family=family)
        if not is_family_manager(request.user, family):
            base = base.filter(
                Q(owner=request.user) | Q(created_by=request.user)
            )
        qs = _after_cursor(base.order_by("updated_at", "id"), cursor)
        rows = list(qs[: WALLET_PULL_LIMIT + 1])
        has_more = len(rows) > WALLET_PULL_LIMIT
        rows = rows[:WALLET_PULL_LIMIT]
        new_cursor = _cursor_of(rows[-1]) if rows else cursor
        return Response(
            {
                "results": WalletSerializer(rows, many=True).data,
                "cursor": new_cursor,
                "has_more": has_more,
            }
        )

    def post(self, request):
        family = resolve_family(request.user, request.data.get("family"))
        items = request.data.get("wallets")
        if not isinstance(items, list):
            raise ValidationError({"wallets": "باید یک لیست باشد"})
        member_ids = set(
            str(i)
            for i in FamilyMembership.objects.filter(family=family).values_list(
                "user_id", flat=True
            )
        )
        results = upsert_each(
            items, lambda item: self._upsert(item, family, member_ids, request.user)
        )
        return Response({"success": True, "results": results})

    def _upsert(self, item, family, member_ids, user):
        if not isinstance(item, dict) or not item.get("id"):
            raise ValidationError({"wallets": "هر کیف باید id داشته باشد"})
        serializer = WalletSerializer(data=item)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        wid = item["id"]

        owner_id = data.get("owner_id") or None
        if owner_id is not None and str(owner_id) not in member_ids:
            owner_id = None  # صاحبِ خارج از خانواده نادیده گرفته می‌شود

        existing = Wallet.objects.filter(id=wid).first()
        if existing is not None and existing.family_id != family.id:
            raise NotFound()  # کیفِ خانواده‌ی دیگر
        fields = {
            "family": family,
            "owner_id": owner_id,
            "owner_name": data.get("owner_name", ""),
            "label": data.get("label", ""),
            "bank_id": data.get("bank_id", ""),
            "card_last4": data.get("card_last4", ""),
            "account_ref": data.get("account_ref", ""),
            "is_deleted": data.get("is_deleted", False),
            "client_updated_at": data.get("client_updated_at"),
        }
        # گوشیِ نسخه‌ی قدیمی «archived» نمی‌فرستد؛ نبودنش مقدارِ قبلی را پاک نمی‌کند.
        if "archived" in item:
            fields["archived"] = data.get("archived", False)
        if existing is None:
            fields["created_by"] = user
            wallet = Wallet.objects.create(id=wid, **fields)
        else:
            for k, v in fields.items():
                setattr(existing, k, v)
            existing.save()
            wallet = existing
        return WalletSerializer(wallet).data, existing is None
