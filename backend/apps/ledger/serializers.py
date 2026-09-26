from rest_framework import serializers

from .models import LedgerCheckpoint, LedgerEntry, LedgerSettings, SmsDecision


class _BlankIfNull(serializers.CharField):
    """متنِ اختیاری: null از گوشی = رشته‌ی خالی (ستون‌ها null نمی‌پذیرند)."""

    def validate_empty_values(self, data):
        if data is None:
            return True, ""
        return super().validate_empty_values(data)


def _text(max_length):
    return _BlankIfNull(max_length=max_length, required=False, allow_blank=True, default="")


class LedgerEntrySerializer(serializers.ModelSerializer):
    sms_key = _text(100)
    note = _text(500)
    created_by_device = _text(64)
    categories = serializers.ListField(
        child=serializers.CharField(max_length=100), required=False, max_length=20, default=list
    )

    class Meta:
        model = LedgerEntry
        fields = [
            "id",
            "account_id",
            "kind",
            "is_transfer",
            "transfer_pair_id",
            "amount_rial",
            "occurred_at",
            "bank_balance_after",
            "source",
            "sms_key",
            "note",
            "categories",
            "created_by_device",
            "client_updated_at",
            "deleted_at",
            "updated_at",
        ]
        read_only_fields = ["id", "updated_at"]

    def validate_amount_rial(self, value):
        if value <= 0:
            raise serializers.ValidationError("مبلغ باید مثبت باشد")
        return value


class LedgerCheckpointSerializer(serializers.ModelSerializer):
    note = _text(500)

    class Meta:
        model = LedgerCheckpoint
        fields = [
            "id",
            "account_id",
            "at",
            "balance_rial",
            "note",
            "client_updated_at",
            "deleted_at",
            "updated_at",
        ]
        read_only_fields = ["id", "updated_at"]


class SmsDecisionSerializer(serializers.ModelSerializer):
    reject_reason = _text(12)

    class Meta:
        model = SmsDecision
        fields = [
            "key",
            "content_hash",
            "received_at",
            "status",
            "reject_reason",
            "entry_id",
            "decided_at",
            "updated_at",
        ]
        read_only_fields = ["updated_at"]


class LedgerSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = LedgerSettings
        fields = ["enabled", "start_date", "setup_done", "updated_at"]
        read_only_fields = ["updated_at"]
