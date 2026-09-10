from rest_framework import generics, permissions

from .serializers import RegisterSerializer, UserSerializer


class RegisterView(generics.CreateAPIView):
    """ثبت‌نام کاربر جدید (باز برای همه)."""

    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]


class MeView(generics.RetrieveAPIView):
    """اطلاعات کاربر جاری."""

    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
