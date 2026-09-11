from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import MeView, ThrottledLoginView

# ثبت‌نام عمومی نداریم: کاربرها را مدیر در پنل ادمین (/admin/) می‌سازد.
urlpatterns = [
    path("login/", ThrottledLoginView.as_view(), name="auth-login"),
    path("refresh/", TokenRefreshView.as_view(), name="auth-refresh"),
    path("me/", MeView.as_view(), name="auth-me"),
]
