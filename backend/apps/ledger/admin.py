from django.contrib import admin

from .models import LedgerCheckpoint, LedgerEntry, LedgerSettings, SmsDecision


@admin.register(LedgerEntry)
class LedgerEntryAdmin(admin.ModelAdmin):
    list_display = ("occurred_at", "kind", "amount_rial", "source", "created_by", "deleted_at")
    list_filter = ("kind", "source", "family")
    ordering = ("-occurred_at",)


@admin.register(LedgerCheckpoint)
class LedgerCheckpointAdmin(admin.ModelAdmin):
    list_display = ("at", "balance_rial", "created_by", "deleted_at")
    ordering = ("-at",)


@admin.register(SmsDecision)
class SmsDecisionAdmin(admin.ModelAdmin):
    list_display = ("received_at", "status", "reject_reason", "user")
    list_filter = ("status",)


@admin.register(LedgerSettings)
class LedgerSettingsAdmin(admin.ModelAdmin):
    list_display = ("user", "enabled", "start_date", "setup_done")
