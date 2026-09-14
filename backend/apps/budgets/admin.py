from django.contrib import admin

from .models import Budget


@admin.register(Budget)
class BudgetAdmin(admin.ModelAdmin):
    list_display = ("category_name", "family", "period", "limit_rial", "is_deleted")
    list_filter = ("family", "period", "is_deleted")
    search_fields = ("category_name",)
