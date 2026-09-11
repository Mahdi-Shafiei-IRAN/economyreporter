from django.contrib import admin

from .models import Budget


@admin.register(Budget)
class BudgetAdmin(admin.ModelAdmin):
    list_display = ("category", "family", "period", "limit_rial")
    list_filter = ("family", "period")
