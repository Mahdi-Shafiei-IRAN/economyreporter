import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q


class Transaction(models.Model):
    """قلب سیستم. مبلغ کانونی به ریال (عدد صحیح). id از دستگاه می‌آید (idempotency)."""

    class Kind(models.TextChoices):
        INCOME = "income", "درآمد"
        EXPENSE = "expense", "هزینه"
        TRANSFER = "transfer", "انتقال"  # جابه‌جایی داخلی؛ در جمع درآمد/هزینه نیست

    class Source(models.TextChoices):
        SMS = "sms", "پیامک"
        MANUAL = "manual", "دستی"
        NOTIFICATION = "notification", "اعلان"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="transactions",
        verbose_name="خانواده",
    )
    # صاحب تراکنش = عضوی که کارت/حساب مال اوست (فقط او ویرایش/دسته‌بندی می‌کند).
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="transactions",
        verbose_name="صاحب کارت",
    )
    # عضوی که پیامک روی گوشی‌اش رسید و تراکنش را فرستاد (تعیین صاحب کارت با اوست).
    captured_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="captured_transactions",
        verbose_name="پیامک روی گوشیِ",
    )
    # نام نمایشی صاحب و برچسب کارت (از «کیف»های گوشیِ دریافت‌کننده).
    person_name = models.CharField("نام صاحب", max_length=100, blank=True)
    wallet_label = models.CharField("برچسب کارت", max_length=100, blank=True)
    bank_id = models.CharField("بانک", max_length=50, blank=True)
    card_last4 = models.CharField("۴ رقم کارت", max_length=4, blank=True)  # فقط ۴ رقم آخر
    account = models.ForeignKey(
        "accounts.BankAccount",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
        verbose_name="حساب",
    )
    card = models.ForeignKey(
        "accounts.Card",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
        verbose_name="کارت",
    )
    category = models.ForeignKey(
        "categories.Category",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="transactions",
        verbose_name="دسته",
    )

    kind = models.CharField("نوع", max_length=10, choices=Kind.choices)

    # پول: مبلغ کانونی همیشه ریال (صحیح). null برای موارد نیازمند بازبینی.
    amount_rial = models.BigIntegerField("مبلغ (ریال)", null=True, blank=True)
    balance_after_rial = models.BigIntegerField("مانده بعد (ریال)", null=True, blank=True)
    raw_amount = models.CharField("مبلغ خام", max_length=32, blank=True)
    raw_unit = models.CharField("واحد خام", max_length=8, default="rial")

    counterparty = models.CharField("طرف حساب / بابت", max_length=200, blank=True)
    description = models.TextField("توضیح", blank=True)

    # تخصیص مبلغ به چند دسته: [{"name": "میوه", "amount_rial": 50000}, ...]
    allocations = models.JSONField("دسته‌ها", default=list, blank=True)

    # حذف نرم: برای تراکنش‌های نامعتبر (ناموفق/پیامک رمز)؛ به بقیه‌ی گوشی‌ها هم می‌رسد.
    is_deleted = models.BooleanField("نامعتبر (حذف‌شده)", default=False)

    # زمان آخرین ویرایش روی دستگاه؛ برای «آخرین ویرایش برنده است» در sync.
    client_updated_at = models.DateTimeField("آخرین ویرایش روی گوشی", null=True, blank=True)

    # دو طرف یک انتقال با این شناسه به هم لینک می‌شوند.
    transfer_group = models.UUIDField(null=True, blank=True, db_index=True)

    source = models.CharField(
        "منبع", max_length=20, choices=Source.choices, default=Source.SMS
    )
    source_message_hash = models.CharField("اثرانگشت پیامک", max_length=64, blank=True)
    device_id = models.CharField("شناسه‌ی گوشی", max_length=64, blank=True)
    needs_review = models.BooleanField("منتظر بازبینی", default=False)

    transaction_date = models.DateTimeField("زمان تراکنش", null=True, blank=True)
    client_created_at = models.DateTimeField("زمان ثبت روی گوشی", null=True, blank=True)
    server_received_at = models.DateTimeField("زمان رسیدن به سرور", auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField("آخرین تغییر", auto_now=True)

    class Meta:
        verbose_name = "تراکنش"
        verbose_name_plural = "تراکنش‌ها"
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
        return self.person_name or self.owner.full_name or self.owner.phone or ""
