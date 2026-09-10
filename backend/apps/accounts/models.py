import uuid

from django.conf import settings
from django.db import models


class BankAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup", on_delete=models.CASCADE, related_name="accounts"
    )
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="accounts"
    )
    bank_name = models.CharField(max_length=100)
    # شناسه‌ی بانک هم‌راستا با رجیستری پارسر موبایل (mellat, melli, ...)؛ برای
    # اتصال خودکار تراکنش پارس‌شده به حساب.
    bank_id = models.CharField(max_length=50, blank=True)
    account_number_masked = models.CharField(max_length=32, blank=True)
    account_type = models.CharField(max_length=30, default="checking")
    currency = models.CharField(max_length=3, default="IRR")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [models.Index(fields=["family", "owner"])]

    def __str__(self):
        return f"{self.bank_name} ({self.owner})"


class Card(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account = models.ForeignKey(
        BankAccount, on_delete=models.CASCADE, related_name="cards"
    )
    card_last4 = models.CharField(max_length=4)  # فقط ۴ رقم آخر — هرگز PAN کامل
    card_label = models.CharField(max_length=100, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["account", "card_last4"], name="unique_card_per_account"
            )
        ]

    def __str__(self):
        return f"**** {self.card_last4}"
