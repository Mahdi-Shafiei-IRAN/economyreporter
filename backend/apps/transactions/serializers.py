from rest_framework import serializers

from .models import Transaction

# فیلدهای متنی که دستگاه ممکن است null بفرستد؛ مدل null=False دارد، پس null → "".
# (قبلاً همین باعث می‌شد sync بیشتر تراکنش‌ها با خطای «may not be null» رد شود.)
_NULLABLE_TEXT = (
    "raw_amount",
    "counterparty",
    "description",
    "source_message_hash",
    "device_id",
    "person_name",
    "wallet_label",
    "bank_id",
    "card_last4",
)


class TransactionSerializer(serializers.ModelSerializer):
    # id از دستگاه می‌آید (idempotency)؛ اگر داده نشود، سرور تولید می‌کند.
    id = serializers.UUIDField(required=False)
    family = serializers.PrimaryKeyRelatedField(read_only=True)
    owner = serializers.PrimaryKeyRelatedField(read_only=True)
    captured_by = serializers.PrimaryKeyRelatedField(read_only=True)
    owner_name = serializers.CharField(read_only=True)
    # صریح تعریف می‌شود تا به‌خاطر UniqueConstraint اجباری نشود؛ dedup را خودمان
    # (در view/sync + ایندکس جزئی دیتابیس) مدیریت می‌کنیم.
    source_message_hash = serializers.CharField(
        required=False, allow_blank=True, max_length=64, default=""
    )
    allocations = serializers.JSONField(required=False)

    class Meta:
        model = Transaction
        fields = [
            "id",
            "family",
            "owner",
            "owner_name",
            "captured_by",
            "person_name",
            "wallet_label",
            "bank_id",
            "card_last4",
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
            "allocations",
            "transfer_group",
            "source",
            "source_message_hash",
            "device_id",
            "needs_review",
            "is_deleted",
            "transaction_date",
            "client_created_at",
            "client_updated_at",
            "server_received_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "family",
            "owner",
            "captured_by",
            "server_received_at",
            "created_at",
            "updated_at",
        ]

    def get_unique_together_validators(self):
        # ضدتکرار را خودمان مدیریت می‌کنیم (view/sync + ایندکس جزئی دیتابیس).
        # validator خودکارِ DRF شرط جزئیِ UniqueConstraint را نمی‌فهمد.
        return []

    def to_internal_value(self, data):
        if isinstance(data, dict):
            data = {
                k: ("" if v is None and k in _NULLABLE_TEXT else v)
                for k, v in data.items()
            }
        return super().to_internal_value(data)

    def validate_allocations(self, value):
        if value in (None, ""):
            return []
        if not isinstance(value, list):
            raise serializers.ValidationError("باید یک لیست باشد")
        clean = []
        for item in value:
            if not isinstance(item, dict):
                raise serializers.ValidationError("هر تخصیص باید یک شیء باشد")
            name = str(item.get("name") or "").strip()[:100]
            amount = item.get("amount_rial")
            if not name or not isinstance(amount, int) or isinstance(amount, bool) or amount < 0:
                raise serializers.ValidationError("تخصیص نامعتبر")
            clean.append({"name": name, "amount_rial": amount})
        return clean
