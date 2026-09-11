from django.contrib import admin

from .models import Category


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ("name", "family", "is_system")
    list_filter = ("family", "is_system")
    search_fields = ("name",)
