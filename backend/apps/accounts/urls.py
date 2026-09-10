from rest_framework.routers import DefaultRouter

from .views import BankAccountViewSet, CardViewSet

router = DefaultRouter()
router.register("accounts", BankAccountViewSet, basename="account")
router.register("cards", CardViewSet, basename="card")

urlpatterns = router.urls
