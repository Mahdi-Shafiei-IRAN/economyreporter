"""همگام‌سازیِ دفترِ نسخه‌ی ۲ (docs/v2-design.md ۱۲.۷). در فاز ۴ هر کاربر فقط دادهٔ خودش را
می‌فرستد و می‌گیرد (پشتیبان و بازگشت بعد از نصبِ دوباره)."""
import uuid

from django.db.models import Q
from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.family import resolve_family
from apps.common.sync import upsert_each

from .models import LedgerCheckpoint, LedgerEntry, LedgerSettings, SmsDecision
from .serializers import (
    LedgerCheckpointSerializer,
    LedgerEntrySerializer,
    LedgerSettingsSerializer,
    SmsDecisionSerializer,
)

PULL_LIMIT = 500


def _cursor_of(row):
    return f"{row.updated_at.isoformat()}|{row.pk}"


def _after_cursor(qs, cursor, parse_pk):
    """cursor = «updated_at|pk»؛ ردیف‌های هم‌زمان با pk بزرگ‌تر هم می‌آیند (در مرزِ صفحه جا نمانند)."""
    if not cursor:
        return qs
    stamp, _, last = cursor.partition("|")
    since = parse_datetime(stamp)
    if since is None:
        return qs
    try:
        last_pk = parse_pk(last) if last else None
    except (ValueError, TypeError):
        last_pk = None
    if last_pk is None:
        return qs.filter(updated_at__gt=since)
    return qs.filter(Q(updated_at__gt=since) | Q(updated_at=since, pk__gt=last_pk))


def _page(qs, cursor, parse_pk, serializer):
    rows = list(_after_cursor(qs.order_by("updated_at", "pk"), cursor, parse_pk)[: PULL_LIMIT + 1])
    has_more = len(rows) > PULL_LIMIT
    rows = rows[:PULL_LIMIT]
    return Response(
        {
            "results": serializer(rows, many=True).data,
            "cursor": _cursor_of(rows[-1]) if rows else cursor,
            "has_more": has_more,
        }
    )


class _OwnedSyncView(APIView):
    """تراکنش/نقطه: GET = ردیف‌های خودم از cursor؛ POST = upsert دسته‌ای با شناسه‌ی گوشی."""

    model = None
    serializer = None
    items_key = None

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        qs = self.model.objects.filter(family=family, created_by=request.user)
        return _page(qs, request.query_params.get("since") or None, uuid.UUID, self.serializer)

    def post(self, request):
        family = resolve_family(request.user, request.data.get("family"))
        items = request.data.get(self.items_key)
        if not isinstance(items, list):
            raise ValidationError({self.items_key: "باید یک لیست باشد"})
        return Response(
            {"success": True, "results": upsert_each(items, lambda i: self._upsert(i, family, request.user))}
        )

    def _upsert(self, item, family, user):
        if not isinstance(item, dict) or not item.get("id"):
            raise ValidationError({self.items_key: "هر ردیف باید id داشته باشد"})
        ser = self.serializer(data=item)
        ser.is_valid(raise_exception=True)
        data = dict(ser.validated_data)
        existing = self.model.objects.filter(id=item["id"]).first()
        if existing is not None:
            if existing.family_id != family.id:
                raise NotFound()
            if existing.created_by_id != user.id:
                raise PermissionDenied()
            incoming = data.get("client_updated_at")
            if existing.client_updated_at and incoming and existing.client_updated_at > incoming:
                # نسخه‌ی سرور جدیدتر است: همان را برگردان تا گوشی بگیرد.
                return {**self.serializer(existing).data, "status": "stale"}, False
            for k, v in data.items():
                setattr(existing, k, v)
            existing.save()
            return self.serializer(existing).data, False
        row = self.model.objects.create(id=item["id"], family=family, created_by=user, **data)
        return self.serializer(row).data, True


class EntrySyncView(_OwnedSyncView):
    model = LedgerEntry
    serializer = LedgerEntrySerializer
    items_key = "entries"


class CheckpointSyncView(_OwnedSyncView):
    model = LedgerCheckpoint
    serializer = LedgerCheckpointSerializer
    items_key = "checkpoints"


class DecisionSyncView(APIView):
    """تصمیم‌های پیامکِ خودم (کلیدِ پیامک یکتاست). تصمیمِ جدیدتر (decided_at) برنده است."""

    def get(self, request):
        qs = SmsDecision.objects.filter(user=request.user)
        return _page(qs, request.query_params.get("since") or None, int, SmsDecisionSerializer)

    def post(self, request):
        items = request.data.get("decisions")
        if not isinstance(items, list):
            raise ValidationError({"decisions": "باید یک لیست باشد"})
        return Response(
            {"success": True, "results": upsert_each(items, lambda i: self._upsert(i, request.user))}
        )

    def _upsert(self, item, user):
        """نتیجه: `{key, status}`؛ برای `stale` نسخه‌ی سرور در `decision` (خودِ تصمیم هم فیلدِ
        status دارد، پس کنارِ status نتیجه نمی‌آید)."""
        if not isinstance(item, dict):
            raise ValidationError({"decisions": "هر تصمیم باید یک شیء باشد"})
        ser = SmsDecisionSerializer(data=item)
        ser.is_valid(raise_exception=True)
        data = dict(ser.validated_data)
        existing = SmsDecision.objects.filter(user=user, key=data["key"]).first()
        if existing is None:
            SmsDecision.objects.create(user=user, **data)
            return {"key": data["key"]}, True
        incoming = data.get("decided_at")
        if existing.decided_at and incoming and existing.decided_at > incoming:
            return {
                "key": existing.key,
                "status": "stale",
                "decision": SmsDecisionSerializer(existing).data,
            }, False
        for k, v in data.items():
            setattr(existing, k, v)
        existing.save()
        return {"key": existing.key}, False


class LedgerSettingsView(APIView):
    """روشن‌بودنِ نسخه‌ی ۲، تاریخِ شروع و راهنما — تا نصبِ دوباره همان را برگرداند."""

    def get(self, request):
        row, _ = LedgerSettings.objects.get_or_create(user=request.user)
        return Response(LedgerSettingsSerializer(row).data)

    def put(self, request):
        row, _ = LedgerSettings.objects.get_or_create(user=request.user)
        ser = LedgerSettingsSerializer(row, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data)
