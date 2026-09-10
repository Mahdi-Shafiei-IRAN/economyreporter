from rest_framework import serializers

from .models import BankAccount, Card


class BankAccountSerializer(serializers.ModelSerializer):
    owner = serializers.PrimaryKeyRelatedField(read_only=True)
    family = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = BankAccount
        fields = [
            "id",
            "family",
            "owner",
            "bank_name",
            "bank_id",
            "account_number_masked",
            "account_type",
            "currency",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "family", "owner", "created_at", "updated_at"]


class CardSerializer(serializers.ModelSerializer):
    class Meta:
        model = Card
        fields = ["id", "account", "card_last4", "card_label", "created_at"]
        read_only_fields = ["id", "created_at"]
