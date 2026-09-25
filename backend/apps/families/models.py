import uuid

from django.conf import settings
from django.db import models


class FamilyGroup(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField("نام خانواده", max_length=150)
    created_at = models.DateTimeField("زمان ساخت", auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "خانواده"
        verbose_name_plural = "خانواده‌ها"

    def __str__(self):
        return self.name


class FamilyMembership(models.Model):
    class Role(models.TextChoices):
        OWNER = "owner", "مدیر خانواده"
        MEMBER = "member", "عضو"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        FamilyGroup,
        on_delete=models.CASCADE,
        related_name="memberships",
        verbose_name="خانواده",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="family_memberships",
        verbose_name="کاربر",
    )
    role = models.CharField(
        "نقش", max_length=20, choices=Role.choices, default=Role.MEMBER
    )
    joined_at = models.DateTimeField("زمان عضویت", auto_now_add=True)

    class Meta:
        verbose_name = "عضو خانواده"
        verbose_name_plural = "اعضای خانواده"
        constraints = [
            models.UniqueConstraint(
                fields=["family", "user"], name="unique_family_member"
            )
        ]

    def __str__(self):
        return f"{self.user} @ {self.family} ({self.role})"


class DeviceHealth(models.Model):
    """خلاصه‌ی «سلامت» برنامه روی یک گوشی، که خودِ گوشی می‌فرستد تا مدیرِ خانواده ببیند
    برنامه روی گوشیِ بقیه درست کار می‌کند یا نه.

    فقط شمارش‌ها، نام بانک‌ها، مبلغِ اختلاف‌ها و نسخه — **هیچ متنِ پیامک، شماره‌ی حساب یا
    سرشماره‌ای در آن نیست** (گوشی همین را تضمین می‌کند و اینجا هم اندازه‌اش محدود است).
    """

    class Level(models.TextChoices):
        OK = "ok", "سالم"
        WARN = "warn", "نیاز به بررسی"
        BAD = "bad", "مشکل"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="device_health",
        verbose_name="کاربر",
    )
    device_id = models.CharField("شناسه‌ی گوشی", max_length=64)
    app_version = models.CharField("نسخه‌ی برنامه", max_length=32, blank=True)
    level = models.CharField("وضعیت", max_length=8, choices=Level.choices)
    summary = models.JSONField("خلاصه", default=dict, blank=True)
    reported_at = models.DateTimeField("زمانِ گزارش (گوشی)")
    updated_at = models.DateTimeField("زمانِ دریافت", auto_now=True)

    class Meta:
        verbose_name = "سلامتِ گوشی"
        verbose_name_plural = "سلامتِ گوشی‌ها"
        constraints = [
            models.UniqueConstraint(fields=["user", "device_id"], name="unique_device_health")
        ]

    def __str__(self):
        return f"{self.user} / {self.device_id} ({self.level})"
