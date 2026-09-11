from django.contrib import admin
from django.utils import timezone

from .models import Transaction


@admin.register(Transaction)
class TransactionAdmin(admin.ModelAdmin):
    """فهرست تراکنش‌های رسیده از گوشی‌ها. متن پیامک هرگز روی سرور نیست."""

    list_display = (
        "when",
        "owner_label",
        "kind",
        "amount_toman",
        "counterparty",
        "card_last4",
        "needs_review",
        "is_deleted",
    )
    list_filter = ("family", "kind", "is_deleted", "needs_review", "owner")
    search_fields = (
        "counterparty",
        "description",
        "person_name",
        "wallet_label",
        "card_last4",
        "owner__full_name",
        "owner__phone",
    )
    list_select_related = ("owner",)
    ordering = ("-server_received_at",)
    list_per_page = 50
    actions = ["mark_invalid", "restore"]
    fieldsets = (
        (
            None,
            {"fields": ("kind", "amount_rial", "counterparty", "description", "needs_review", "is_deleted")},
        ),
        (
            "صاحب و کارت",
            {"fields": ("family", "owner", "person_name", "wallet_label", "bank_id", "card_last4", "captured_by")},
        ),
        (
            "جزئیات",
            {
                "classes": ("collapse",),
                "fields": (
                    "allocations",
                    "balance_after_rial",
                    "raw_amount",
                    "raw_unit",
                    "source",
                    "source_message_hash",
                    "device_id",
                ),
            },
        ),
        (
            "زمان‌ها",
            {"fields": ("transaction_date", "client_created_at", "client_updated_at", "server_received_at", "updated_at")},
        ),
    )
    readonly_fields = (
        "family",
        "owner",
        "person_name",
        "wallet_label",
        "bank_id",
        "card_last4",
        "captured_by",
        "allocations",
        "balance_after_rial",
        "raw_amount",
        "raw_unit",
        "source",
        "source_message_hash",
        "device_id",
        "transaction_date",
        "client_created_at",
        "client_updated_at",
        "server_received_at",
        "updated_at",
    )

    def has_add_permission(self, request):
        return False  # تراکنش‌ها از پیامکِ گوشی‌ها می‌آیند

    @admin.display(description="زمان", ordering="transaction_date")
    def when(self, obj):
        return obj.transaction_date or obj.server_received_at

    @admin.display(description="صاحب")
    def owner_label(self, obj):
        return obj.owner_name

    @admin.display(description="مبلغ (تومان)", ordering="amount_rial")
    def amount_toman(self, obj):
        return "—" if obj.amount_rial is None else f"{obj.amount_rial // 10:,}"

    # update() زمان updated_at را خودکار عوض نمی‌کند؛ صریحاً می‌دهیم تا گوشی‌ها
    # در همگام‌سازی بعدی تغییر را بگیرند.
    @admin.action(description="نامعتبر کن (از جمع‌ها و از گوشی‌ها هم حذف می‌شود)")
    def mark_invalid(self, request, queryset):
        n = queryset.update(is_deleted=True, updated_at=timezone.now())
        self.message_user(request, f"{n} تراکنش نامعتبر شد.")

    @admin.action(description="برگرداندن (دوباره معتبر)")
    def restore(self, request, queryset):
        n = queryset.update(is_deleted=False, updated_at=timezone.now())
        self.message_user(request, f"{n} تراکنش برگشت.")
