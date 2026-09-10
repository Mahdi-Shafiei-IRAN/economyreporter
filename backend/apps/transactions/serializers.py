from rest_framework import serializers

from .models import Transaction


class TransactionSerializer(serializers.ModelSerializer):
    # id از دستگاه می‌آید (idempotency)؛ اگر داده نشود، سرور تولید می‌کند.
    id = serializers.UUIDField(required=False)
    family = serializers.PrimaryKeyRelatedField(read_only=True)
    owner = serializers.PrimaryKeyRelatedField(read_only=True)
    # صریح تعریف می‌شود تا به‌خاطر UniqueConstraint اجباری نشود؛ dedup را خودمان
    # (در view/sync + ایندکس جزئی دیتابیس) مدیریت می‌کنیم.
    source_message_hash = serializers.CharField(
        required=False, allow_blank=True, max_length=64, default=""
    )

    class Meta:
        model = Transaction
        fields = [
            "id",
            "family",
            "owner",
            "account",
            "card",
            "category",
            "kind",
            "amount_rial",
            "balance_after_rial",
            "raw_amount",
            "raw_unit",
            "counterparty",
            "description",
            "transfer_group",
            "source",
            "source_message_hash",
            "device_id",
            "needs_review",
            "transaction_date",
            "client_created_at",
            "server_received_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "family",
            "owner",
            "server_received_at",
            "created_at",
            "updated_at",
        ]

    def get_unique_together_validators(self):
        # ضدتکرار را خودمان مدیریت می‌کنیم (view/sync + ایندکس جزئی دیتابیس).
        # validator خودکارِ DRF شرط جزئیِ UniqueConstraint را نمی‌فهمد.
        return []
