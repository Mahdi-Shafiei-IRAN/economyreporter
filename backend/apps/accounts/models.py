import uuid

from django.conf import settings
from django.db import models


class BankAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="accounts",
        verbose_name="خانواده",
    )
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="accounts",
        verbose_name="صاحب",
    )
    bank_name = models.CharField("بانک", max_length=100)
    # شناسه‌ی بانک هم‌راستا با رجیستری پارسر موبایل (mellat, melli, ...)؛ برای
    # اتصال خودکار تراکنش پارس‌شده به حساب.
    bank_id = models.CharField("شناسه‌ی بانک", max_length=50, blank=True)
    account_number_masked = models.CharField("شماره حساب (ماسک‌شده)", max_length=32, blank=True)
    account_type = models.CharField("نوع حساب", max_length=30, default="checking")
    currency = models.CharField("ارز", max_length=3, default="IRR")
    is_active = models.BooleanField("فعال", default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "حساب بانکی"
        verbose_name_plural = "حساب‌های بانکی"
        indexes = [models.Index(fields=["family", "owner"])]

    def __str__(self):
        return f"{self.bank_name} ({self.owner})"


class Wallet(models.Model):
    """کیفِ اپ: کارت/حسابِ یک عضو (شناسه از سمت کلاینت می‌آید تا آفلاین ساخته شود).

    نسخه‌ی هم‌گام‌شونده‌ی همان مدل موبایل؛ برای اینکه اعضای خانواده کارت‌های هم را
    ببینند و صاحبِ هر تراکنش یکسان تعیین شود. شماره‌ی کاملِ کارت هرگز ذخیره نمی‌شود.
    """

    id = models.UUIDField(primary_key=True, editable=False)  # UUIDِ ساخته‌شده در گوشی
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="wallets",
        verbose_name="خانواده",
    )
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="wallets",
        verbose_name="صاحب",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="wallets_created",
        verbose_name="سازنده",
    )
    owner_name = models.CharField("نام صاحب", max_length=100, blank=True)
    label = models.CharField("برچسب", max_length=100, blank=True)
    bank_id = models.CharField("شناسه‌ی بانک", max_length=50, blank=True)
    card_last4 = models.CharField("۴ رقم کارت", max_length=4, blank=True)
    account_ref = models.CharField("شماره حساب", max_length=32, blank=True)
    is_deleted = models.BooleanField("حذف‌شده", default=False)
    # نسخه‌ی ۲: «پیگیری نشود» (حسابِ کنارگذاشته).
    archived = models.BooleanField("کنارگذاشته", default=False)
    client_updated_at = models.DateTimeField("آخرین ویرایش روی گوشی", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField("آخرین تغییر", auto_now=True)

    class Meta:
        verbose_name = "کیف (کارت/حساب)"
        verbose_name_plural = "کیف‌ها (کارت/حساب)"
        indexes = [
            models.Index(fields=["family", "updated_at"]),
            models.Index(fields=["family", "owner"]),
        ]

    def __str__(self):
        return f"{self.label or self.owner_name} ({self.owner_name})"


class Card(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account = models.ForeignKey(
        BankAccount, on_delete=models.CASCADE, related_name="cards", verbose_name="حساب"
    )
    card_last4 = models.CharField("۴ رقم آخر کارت", max_length=4)  # هرگز PAN کامل
    card_label = models.CharField("برچسب", max_length=100, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "کارت"
        verbose_name_plural = "کارت‌ها"
        constraints = [
            models.UniqueConstraint(
                fields=["account", "card_last4"], name="unique_card_per_account"
            )
        ]

    def __str__(self):
        return f"**** {self.card_last4}"
