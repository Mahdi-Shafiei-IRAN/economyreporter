from rest_framework import serializers

from .models import Budget


class BudgetSerializer(serializers.ModelSerializer):
    family = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Budget
        fields = ["id", "family", "category", "period", "limit_rial", "created_at"]
        read_only_fields = ["id", "family", "created_at"]
