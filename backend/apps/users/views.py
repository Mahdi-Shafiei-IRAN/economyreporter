from django.db import transaction
from rest_framework import generics, status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView

from apps.families.models import FamilyGroup, FamilyMembership

from .serializers import RegisterSerializer, UserSerializer


class ThrottledLoginView(TokenObtainPairView):
    """ورود JWT با شماره موبایل + رمز، با محدودیت نرخ (ضد brute-force).

    شماره به هر شکلی (09…، +98…، ارقام فارسی) پذیرفته می‌شود؛ نرمال‌سازی در
    UserManager.get_by_natural_key است.
    """

    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"


def _tokens_for(user):
    refresh = RefreshToken.for_user(user)
    return {"refresh": str(refresh), "access": str(refresh.access_token)}


class RegisterView(APIView):
    """ثبت‌نامِ آزاد: هرکس می‌تواند حساب و خانواده‌ی خودش را بسازد و مالکش شود.

    خروجی = توکن‌ها + کاربر، تا اپ بلافاصله وارد شود.
    """

    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "auth"

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            user = serializer.create_user()
            name = serializer.validated_data.get("family_name", "").strip()
            family = FamilyGroup.objects.create(
                name=name or f"خانواده‌ی {user.full_name or user.phone}"
            )
            FamilyMembership.objects.create(
                family=family, user=user, role=FamilyMembership.Role.OWNER
            )
        return Response(
            {
                "user": UserSerializer(user).data,
                "family": {"id": str(family.id), "name": family.name},
                **_tokens_for(user),
            },
            status=status.HTTP_201_CREATED,
        )


class MeView(generics.RetrieveAPIView):
    """اطلاعات کاربر جاری."""

    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user
