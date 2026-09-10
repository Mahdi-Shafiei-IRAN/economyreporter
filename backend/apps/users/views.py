from rest_framework import generics, permissions
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import RegisterSerializer, UserSerializer


class RegisterView(generics.CreateAPIView):
    """ثبت‌نام کاربر جدید (باز برای همه، با محدودیت نرخ)."""

    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class ThrottledLoginView(TokenObtainPairView):
    """ورود JWT با محدودیت نرخ (ضد brute-force)."""

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class MeView(generics.RetrieveAPIView):
    """اطلاعات کاربر جاری."""

    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
