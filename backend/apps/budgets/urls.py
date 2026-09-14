from django.urls import path

from .views import BudgetSyncView

urlpatterns = [
    path("budgets/sync/", BudgetSyncView.as_view(), name="budget-sync"),
]
