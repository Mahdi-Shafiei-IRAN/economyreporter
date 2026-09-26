from django.urls import path

from .views import CheckpointSyncView, DecisionSyncView, EntrySyncView, LedgerSettingsView

urlpatterns = [
    path("entries/sync/", EntrySyncView.as_view(), name="ledger-entries-sync"),
    path("checkpoints/sync/", CheckpointSyncView.as_view(), name="ledger-checkpoints-sync"),
    path("decisions/sync/", DecisionSyncView.as_view(), name="ledger-decisions-sync"),
    path("settings/", LedgerSettingsView.as_view(), name="ledger-settings"),
]
