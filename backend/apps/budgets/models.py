import uuid

from django.db import models


class Budget(models.Model):
    class Period(models.TextChoices):
        MONTHLY = "monthly", "ماهانه"
        WEEKLY = "weekly", "هفتگی"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="budgets",
        verbose_name="خانواده",
    )
    category = models.ForeignKey(
        "categories.Category",
        on_delete=models.CASCADE,
        related_name="budgets",
        verbose_name="دسته",
    )
    period = models.CharField(
        "دوره", max_length=10, choices=Period.choices, default=Period.MONTHLY
    )
    limit_rial = models.BigIntegerField("سقف (ریال)")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "بودجه"
        verbose_name_plural = "بودجه‌ها"
        constraints = [
            models.UniqueConstraint(
                fields=["family", "category", "period"],
                name="unique_budget_per_category_period",
            )
        ]

    def __str__(self):
        return f"{self.category} {self.period}: {self.limit_rial}"
