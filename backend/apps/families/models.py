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
