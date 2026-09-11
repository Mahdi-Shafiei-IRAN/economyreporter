import uuid

from django.db import models


class Category(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(
        "families.FamilyGroup",
        on_delete=models.CASCADE,
        related_name="categories",
        verbose_name="خانواده",
    )
    name = models.CharField("نام", max_length=100)
    icon = models.CharField("آیکون", max_length=100, blank=True)
    color = models.CharField("رنگ", max_length=20, blank=True)
    is_system = models.BooleanField("پیش‌فرض", default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "دسته"
        verbose_name_plural = "دسته‌ها"
        constraints = [
            models.UniqueConstraint(
                fields=["family", "name"], name="unique_category_name_per_family"
            )
        ]

    def __str__(self):
        return self.name
