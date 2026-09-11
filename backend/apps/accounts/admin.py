from django.contrib import admin

from .models import BankAccount, Card


class CardInline(admin.TabularInline):
    model = Card
    extra = 0
    fields = ("card_last4", "card_label")


@admin.register(BankAccount)
class BankAccountAdmin(admin.ModelAdmin):
    list_display = ("bank_name", "owner", "family", "account_number_masked", "is_active")
    list_filter = ("family", "is_active")
    search_fields = ("bank_name", "account_number_masked", "owner__full_name", "owner__phone")
    list_select_related = ("owner", "family")
    inlines = [CardInline]
