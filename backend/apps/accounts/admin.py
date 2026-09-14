from django.contrib import admin

from .models import BankAccount, Card, Wallet


@admin.register(Wallet)
class WalletAdmin(admin.ModelAdmin):
    list_display = ("label", "owner_name", "owner", "family", "bank_id", "card_last4", "is_deleted")
    list_filter = ("family", "is_deleted", "bank_id")
    search_fields = ("label", "owner_name", "card_last4", "account_ref")
    list_select_related = ("owner", "family")


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
