from rest_framework import viewsets
from rest_framework.exceptions import NotFound

from apps.common.family import user_family_ids

from .models import Budget
from .serializers import BudgetSerializer


class BudgetViewSet(viewsets.ModelViewSet):
    serializer_class = BudgetSerializer

    def get_queryset(self):
        return Budget.objects.filter(
            family_id__in=user_family_ids(self.request.user)
        ).order_by("created_at")

    def perform_create(self, serializer):
        category = serializer.validated_data["category"]
        if category.family_id not in user_family_ids(self.request.user):
            raise NotFound()  # دسته‌ای که نمی‌بینی
        # خانواده‌ی بودجه از دسته گرفته می‌شود تا هم‌خوان بماند.
        serializer.save(family=category.family)
