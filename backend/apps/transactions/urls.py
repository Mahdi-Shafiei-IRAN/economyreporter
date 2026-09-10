from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import DashboardSummaryView, SyncView, TransactionViewSet

router = DefaultRouter()
router.register("transactions", TransactionViewSet, basename="transaction")

urlpatterns = [
    path("sync/transactions/", SyncView.as_view(), name="sync-transactions"),
    path("dashboard/summary/", DashboardSummaryView.as_view(), name="dashboard-summary"),
    *router.urls,
]
