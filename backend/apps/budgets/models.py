import uuid

from django.db import models


class Budget(models.Model):
    class Period(models.TextChoices):
        MONTHLY = "monthly", "Monthly"
        WEEKLY = "weekly", "Weekly"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup", on_delete=models.CASCADE, related_name="budgets"
    )
    category = models.ForeignKey(
        "categories.Category", on_delete=models.CASCADE, related_name="budgets"
    )
    period = models.CharField(
        max_length=10, choices=Period.choices, default=Period.MONTHLY
    )
    limit_rial = models.BigIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["family", "category", "period"],
                name="unique_budget_per_category_period",
            )
        ]

    def __str__(self):
        return f"{self.category} {self.period}: {self.limit_rial}"
