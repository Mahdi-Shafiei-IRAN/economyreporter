import uuid

from django.db.models import Q
from django.utils.dateparse import parse_datetime
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.common.family import resolve_family

from .models import Budget
from .serializers import BudgetSerializer

BUDGET_PULL_LIMIT = 500


def _cursor_of(b):
    return f"{b.updated_at.isoformat()}|{b.id}"


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


class BudgetSyncView(APIView):
    """
    GET: بودجه‌های خانواده از یک cursor به بعد (بودجه‌ها بین همه‌ی اعضا مشترک‌اند).
    POST: آپلود دسته‌ای و idempotent بودجه‌ها (ساخت یا به‌روزرسانی با شناسه‌ی گوشی).
    """

    def get(self, request):
        family = resolve_family(request.user, request.query_params.get("family"))
        cursor = request.query_params.get("since") or None
        qs = _after_cursor(
            Budget.objects.filter(family=family).order_by("updated_at", "id"), cursor
        )
        rows = list(qs[: BUDGET_PULL_LIMIT + 1])
        has_more = len(rows) > BUDGET_PULL_LIMIT
        rows = rows[:BUDGET_PULL_LIMIT]
        new_cursor = _cursor_of(rows[-1]) if rows else cursor
        return Response(
            {
                "results": BudgetSerializer(rows, many=True).data,
                "cursor": new_cursor,
                "has_more": has_more,
            }
        )

    def post(self, request):
        family = resolve_family(request.user, request.data.get("family"))
        items = request.data.get("budgets")
        if not isinstance(items, list):
            raise ValidationError({"budgets": "باید یک لیست باشد"})
        results = [self._upsert(item, family, request.user) for item in items]
        return Response({"success": True, "results": results})

    def _upsert(self, item, family, user):
        if not isinstance(item, dict) or not item.get("id"):
            raise ValidationError({"budgets": "هر بودجه باید id داشته باشد"})
        serializer = BudgetSerializer(data=item)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        bid = item["id"]

        existing = Budget.objects.filter(id=bid).first()
        if existing is not None and existing.family_id != family.id:
            raise NotFound()
        fields = {
            "family": family,
            "category_name": data.get("category_name", ""),
            "period": data.get("period", Budget.Period.MONTHLY),
            "limit_rial": data.get("limit_rial", 0),
            "is_deleted": data.get("is_deleted", False),
            "client_updated_at": data.get("client_updated_at"),
        }
        if existing is None:
            fields["created_by"] = user
            budget = Budget.objects.create(id=bid, **fields)
        else:
            for k, v in fields.items():
                setattr(existing, k, v)
            existing.save()
            budget = existing
        return BudgetSerializer(budget).data
