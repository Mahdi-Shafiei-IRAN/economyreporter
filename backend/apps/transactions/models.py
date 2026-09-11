import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


class Transaction(models.Model):
    """قلب سیستم. مبلغ کانونی به ریال (عدد صحیح). id از دستگاه می‌آید (idempotency)."""

    class Kind(models.TextChoices):
        INCOME = "income", "Income"
        EXPENSE = "expense", "Expense"
        TRANSFER = "transfer", "Transfer"  # جابه‌جایی داخلی؛ در جمع درآمد/هزینه نیست

    class Source(models.TextChoices):
        SMS = "sms", "SMS"
        MANUAL = "manual", "Manual"
        NOTIFICATION = "notification", "Notification"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup", on_delete=models.CASCADE, related_name="transactions"
    )
    # صاحب تراکنش = عضوی که کارت/حساب مال اوست (فقط او ویرایش/دسته‌بندی می‌کند).
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="transactions"
    )
    # عضوی که پیامک روی گوشی‌اش رسید و تراکنش را فرستاد (تعیین صاحب کارت با اوست).
    captured_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="captured_transactions",
    )
    # نام نمایشی صاحب و برچسب کارت (از «کیف»های گوشیِ دریافت‌کننده).
    person_name = models.CharField(max_length=100, blank=True)
    wallet_label = models.CharField(max_length=100, blank=True)
    bank_id = models.CharField(max_length=50, blank=True)
    card_last4 = models.CharField(max_length=4, blank=True)  # فقط ۴ رقم آخر
    account = models.ForeignKey(
        "accounts.BankAccount",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
    )
    card = models.ForeignKey(
        "accounts.Card",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
    )
    category = models.ForeignKey(
        "categories.Category",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
    )

    kind = models.CharField(max_length=10, choices=Kind.choices)

    # پول: مبلغ کانونی همیشه ریال (صحیح). null برای موارد نیازمند بازبینی.
    amount_rial = models.BigIntegerField(null=True, blank=True)
    balance_after_rial = models.BigIntegerField(null=True, blank=True)
    raw_amount = models.CharField(max_length=32, blank=True)
    raw_unit = models.CharField(max_length=8, default="rial")

    counterparty = models.CharField(max_length=200, blank=True)
    description = models.TextField(blank=True)

    # تخصیص مبلغ به چند دسته: [{"name": "میوه", "amount_rial": 50000}, ...]
    allocations = models.JSONField(default=list, blank=True)

    # حذف نرم: برای تراکنش‌های نامعتبر (ناموفق/پیامک رمز)؛ به بقیه‌ی گوشی‌ها هم می‌رسد.
    is_deleted = models.BooleanField(default=False)

    # زمان آخرین ویرایش روی دستگاه؛ برای «آخرین ویرایش برنده است» در sync.
    client_updated_at = models.DateTimeField(null=True, blank=True)

    # دو طرف یک انتقال با این شناسه به هم لینک می‌شوند.
    transfer_group = models.UUIDField(null=True, blank=True, db_index=True)

    source = models.CharField(
        max_length=20, choices=Source.choices, default=Source.SMS
    )
    source_message_hash = models.CharField(max_length=64, blank=True)
    device_id = models.CharField(max_length=64, blank=True)
    needs_review = models.BooleanField(default=False)

    transaction_date = models.DateTimeField(null=True, blank=True)
    client_created_at = models.DateTimeField(null=True, blank=True)
    server_received_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["family", "transaction_date"]),
            models.Index(fields=["family", "owner"]),
            models.Index(fields=["family", "category"]),
            models.Index(fields=["family", "card"]),
            models.Index(fields=["family", "updated_at"]),
        ]
        constraints = [
            # ضدتکرارِ اثرانگشت پیامک در سطح خانواده (فقط برای hashهای غیرخالی).
            models.UniqueConstraint(
                fields=["family", "source_message_hash"],
                condition=~Q(source_message_hash=""),
                name="unique_family_source_hash",
            )
        ]

    def __str__(self):
        return f"{self.kind} {self.amount_rial} ({self.family_id})"

    @property
    def owner_name(self):
        return self.person_name or self.owner.full_name or self.owner.email
