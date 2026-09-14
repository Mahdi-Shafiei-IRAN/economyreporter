from rest_framework import serializers

from .models import Budget


class BudgetSerializer(serializers.ModelSerializer):
    class Meta:
        model = Budget
        fields = [
            "id",
            "category_name",
            "period",
            "limit_rial",
            "is_deleted",
            "client_updated_at",
            "updated_at",
        ]
        read_only_fields = ["updated_at"]
