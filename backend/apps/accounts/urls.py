from django.urls import path
from rest_framework.routers import DefaultRouter

from .views import BankAccountViewSet, CardViewSet, WalletSyncView

router = DefaultRouter()
router.register("accounts", BankAccountViewSet, basename="account")
router.register("cards", CardViewSet, basename="card")

urlpatterns = [
    path("wallets/sync/", WalletSyncView.as_view(), name="wallet-sync"),
    *router.urls,
]
