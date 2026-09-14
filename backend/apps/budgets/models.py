import uuid

from django.conf import settings
from django.db import models


class Budget(models.Model):
    """سقفِ خرجِ ماهانه برای یک دسته (بر اساسِ نامِ دسته، هم‌راستا با allocations).

    نسخه‌ی هم‌گام‌شونده: شناسه از گوشی می‌آید و بودجه‌ها بین اعضای خانواده مشترک‌اند.
    """

    class Period(models.TextChoices):
        MONTHLY = "monthly", "ماهانه"
        WEEKLY = "weekly", "هفتگی"

    id = models.UUIDField(primary_key=True, editable=False)  # UUIDِ ساخته‌شده در گوشی
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="budgets",
        verbose_name="خانواده",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="budgets_created",
        verbose_name="سازنده",
    )
    category_name = models.CharField("نام دسته", max_length=100)
    period = models.CharField(
        "دوره", max_length=10, choices=Period.choices, default=Period.MONTHLY
    )
    limit_rial = models.BigIntegerField("سقف (ریال)")
    is_deleted = models.BooleanField("حذف‌شده", default=False)
    client_updated_at = models.DateTimeField("آخرین ویرایش روی گوشی", null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField("آخرین تغییر", auto_now=True)

    class Meta:
        verbose_name = "بودجه"
        verbose_name_plural = "بودجه‌ها"
        indexes = [models.Index(fields=["family", "updated_at"])]

    def __str__(self):
        return f"{self.category_name} {self.period}: {self.limit_rial}"
