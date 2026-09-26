"""دفترِ حسابِ نسخه‌ی ۲ (docs/v2-design.md بخش ۸ و ۱۲.۷).

همه‌چیز جز متنِ پیامک: تراکنش‌ها، نقطه‌های مانده‌ی دستی، تصمیم‌های کاربر روی پیامک‌ها (بدونِ متن
و فرستنده) و تنظیماتِ کاربر. شناسه‌ها روی گوشی ساخته می‌شوند تا آفلاین کار کند.
"""
from django.conf import settings
from django.db import models


class ClientSynced(models.Model):
    id = models.UUIDField(primary_key=True, editable=False)  # UUIDِ ساخته‌شده در گوشی
    family = models.ForeignKey(
        "families.FamilyGroup", on_delete=models.CASCADE, related_name="+", verbose_name="خانواده"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
        verbose_name="سازنده",
    )
    client_updated_at = models.DateTimeField("آخرین ویرایش روی گوشی", null=True, blank=True)
    deleted_at = models.DateTimeField("حذف", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField("آخرین تغییر", auto_now=True)

    class Meta:
        abstract = True


class LedgerEntry(ClientSynced):
    class Kind(models.TextChoices):
        INCOME = "income", "واریز"
        EXPENSE = "expense", "برداشت"

    class Source(models.TextChoices):
        SMS = "sms", "پیامک"
        MANUAL = "manual", "دستی"
        ADJUSTMENT = "adjustment", "اصلاح"

    account_id = models.UUIDField("حساب (کیف)")
    kind = models.CharField("نوع", max_length=10, choices=Kind.choices)
    is_transfer = models.BooleanField("انتقال بینِ حساب‌های خودم", default=False)
    transfer_pair_id = models.UUIDField(null=True, blank=True)
    amount_rial = models.BigIntegerField("مبلغ (ریال)")
    occurred_at = models.DateTimeField("زمان")
    bank_balance_after = models.BigIntegerField("مانده‌ی بانک بعد از آن", null=True, blank=True)
    source = models.CharField("منبع", max_length=12, choices=Source.choices)
    sms_key = models.CharField("کلیدِ پیامک", max_length=100, blank=True)
    note = models.CharField("یادداشت", max_length=500, blank=True)
    # نامِ دسته‌ها (شناسه‌ی دسته روی هر گوشی فرق دارد).
    categories = models.JSONField("دسته‌ها", default=list, blank=True)
    created_by_device = models.CharField(max_length=64, blank=True)

    class Meta:
        verbose_name = "تراکنشِ دفتر"
        verbose_name_plural = "تراکنش‌های دفتر (نسخه‌ی ۲)"
        indexes = [models.Index(fields=["family", "created_by", "updated_at"])]

    def __str__(self):
        return f"{self.get_kind_display()} {self.amount_rial}"


class LedgerCheckpoint(ClientSynced):
    """«موجودیِ الان» / «تطبیق با موجودیِ واقعی» که کاربر وارد کرده."""

    account_id = models.UUIDField("حساب (کیف)")
    at = models.DateTimeField("زمان")
    balance_rial = models.BigIntegerField("موجودی (ریال)")
    note = models.CharField("یادداشت", max_length=500, blank=True)

    class Meta:
        verbose_name = "نقطه‌ی مانده"
        verbose_name_plural = "نقطه‌های مانده (نسخه‌ی ۲)"
        indexes = [models.Index(fields=["family", "created_by", "updated_at"])]


class SmsDecision(models.Model):
    """تصمیمِ کاربر روی یک پیامک. عمداً بدونِ متن و فرستنده (I6)."""

    class Status(models.TextChoices):
        PENDING = "pending", "منتظر"
        ACCEPTED = "accepted", "ثبت"
        REJECTED = "rejected", "رد"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="+", verbose_name="کاربر"
    )
    key = models.CharField("کلیدِ پیامک", max_length=100)
    content_hash = models.CharField("اثرانگشتِ محتوا", max_length=64)
    received_at = models.DateTimeField("زمانِ رسیدن")
    status = models.CharField("تصمیم", max_length=10, choices=Status.choices)
    reject_reason = models.CharField("دلیلِ رد", max_length=12, blank=True)
    entry_id = models.UUIDField(null=True, blank=True)
    decided_at = models.DateTimeField("زمانِ تصمیم", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "تصمیمِ پیامک"
        verbose_name_plural = "تصمیم‌های پیامک (نسخه‌ی ۲)"
        constraints = [models.UniqueConstraint(fields=["user", "key"], name="unique_decision_per_user")]
        indexes = [models.Index(fields=["user", "updated_at"])]


class LedgerSettings(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, primary_key=True, related_name="+"
    )
    enabled = models.BooleanField("نسخه‌ی ۲ روشن", default=False)
    start_date = models.DateTimeField("تاریخِ شروع", null=True, blank=True)
    setup_done = models.BooleanField("راهنما دیده شده", default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "تنظیماتِ دفتر"
        verbose_name_plural = "تنظیماتِ دفتر (نسخه‌ی ۲)"
