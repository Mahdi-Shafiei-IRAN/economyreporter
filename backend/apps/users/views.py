from rest_framework import generics
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.views import TokenObtainPairView

from .serializers import UserSerializer


class ThrottledLoginView(TokenObtainPairView):
    """ورود JWT با شماره موبایل + رمز، با محدودیت نرخ (ضد brute-force).

    شماره به هر شکلی (09…، +98…، ارقام فارسی) پذیرفته می‌شود؛ نرمال‌سازی در
    UserManager.get_by_natural_key است.
    """

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


class MeView(generics.RetrieveAPIView):
    """اطلاعات کاربر جاری."""

    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
