from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from .views import MeView, RegisterView, ThrottledLoginView

# ثبت‌نامِ آزاد: هرکس حساب و خانواده‌ی خودش را می‌سازد. افزودنِ عضو در /family/.
urlpatterns = [
    path("register/", RegisterView.as_view(), name="auth-register"),
    path("login/", ThrottledLoginView.as_view(), name="auth-login"),
    path("refresh/", TokenRefreshView.as_view(), name="auth-refresh"),
    path("me/", MeView.as_view(), name="auth-me"),
]
