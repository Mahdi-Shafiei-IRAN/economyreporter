from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.users.phone import normalize_phone

from .models import DeviceHealth, FamilyGroup, FamilyMembership
from .permissions import is_member, is_owner
from .serializers import (
    DeviceHealthInSerializer,
    DeviceHealthSerializer,
    FamilyGroupSerializer,
    FamilyMembershipSerializer,
    InviteSerializer,
)

User = get_user_model()


def _get_family_for_member(user, family_id):
    """خانواده را برمی‌گرداند فقط اگر کاربر عضو باشد، وگرنه ۴۰۴ (تا وجودش لو نرود)."""
    family = get_object_or_404(FamilyGroup, id=family_id)
    if not is_member(user, family):
        raise NotFound()
    return family


class FamilyListCreateView(generics.ListCreateAPIView):
    """لیست خانواده‌های کاربر / ساخت خانواده‌ی جدید (سازنده = مالک)."""

    serializer_class = FamilyGroupSerializer

    def get_queryset(self):
        return (
            FamilyGroup.objects.filter(memberships__user=self.request.user)
            .order_by("created_at")
            .distinct()
        )

    def perform_create(self, serializer):
        family = serializer.save()
        FamilyMembership.objects.create(
            family=family,
            user=self.request.user,
            role=FamilyMembership.Role.OWNER,
        )


class FamilyMembersView(APIView):
    """اعضای یک خانواده (فقط برای اعضا)."""

    def get(self, request, family_id):
        family = _get_family_for_member(request.user, family_id)
        memberships = family.memberships.select_related("user").all()
        return Response(FamilyMembershipSerializer(memberships, many=True).data)


class FamilyInviteView(APIView):
    """افزودن عضو به خانواده (فقط مالک؛ بدون سقفِ تعداد)."""

    def post(self, request, family_id):
        family = _get_family_for_member(request.user, family_id)
        if not is_owner(request.user, family):
            raise PermissionDenied("فقط مالک می‌تواند عضو اضافه کند")

        serializer = InviteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        phone = normalize_phone(data["phone"])

        target = User.objects.filter(phone=phone).first()
        if target is None:
            # حسابِ تازه با رمزِ داده‌شده بساز (ثبت‌نامِ آزاد توسط مدیرِ خانواده).
            password = (data.get("password") or "").strip()
            if not password:
                raise ValidationError(
                    "کاربری با این شماره نیست؛ برای ساختِ حساب رمز را هم بده."
                )
            target = User.objects.create_user(
                phone=phone, password=password, full_name=data.get("full_name", "")
            )
        elif is_member(target, family):
            raise ValidationError("این کاربر از قبل عضو خانواده است")

        membership = FamilyMembership.objects.create(
            family=family, user=target, role=FamilyMembership.Role.MEMBER
        )
        return Response(
            FamilyMembershipSerializer(membership).data,
            status=status.HTTP_201_CREATED,
        )


class FamilyMembershipDetailView(APIView):
    """حذف عضو (فقط مالک؛ آخرین مالک حذف نمی‌شود)."""

    def delete(self, request, family_id, membership_id):
        family = _get_family_for_member(request.user, family_id)
        if not is_owner(request.user, family):
            raise PermissionDenied("فقط مالک می‌تواند عضو حذف کند")

        membership = get_object_or_404(
            FamilyMembership, id=membership_id, family=family
        )
        if (
            membership.role == FamilyMembership.Role.OWNER
            and family.memberships.filter(role=FamilyMembership.Role.OWNER).count() <= 1
        ):
            raise ValidationError("آخرین مالک خانواده را نمی‌توان حذف کرد")

        membership.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class DeviceHealthView(APIView):
    """سلامتِ برنامه روی گوشی‌ها.

    POST: گوشی گزارشِ خودش را می‌فرستد (یک ردیف برای هر کاربر + گوشی، جایگزین می‌شود).
    GET: مدیرِ خانواده گوشی‌های همه‌ی اعضا را می‌بیند؛ عضوِ عادی فقط گوشی‌های خودش را.
    """

    def get(self, request):
        owned = FamilyMembership.objects.filter(
            user=request.user, role=FamilyMembership.Role.OWNER
        ).values("family")
        users = set(
            FamilyMembership.objects.filter(family__in=owned).values_list("user", flat=True)
        )
        users.add(request.user.id)
        rows = (
            DeviceHealth.objects.filter(user__in=users)
            .select_related("user")
            .order_by("user__full_name", "user__phone", "-updated_at")
        )
        return Response(DeviceHealthSerializer(rows, many=True).data)

    def post(self, request):
        ser = DeviceHealthInSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        data = ser.validated_data
        row, _ = DeviceHealth.objects.update_or_create(
            user=request.user,
            device_id=data["device_id"],
            defaults={
                "app_version": data.get("app_version", ""),
                "level": data["level"],
                "summary": data.get("summary") or {},
                "reported_at": data.get("reported_at") or timezone.now(),
            },
        )
        return Response(DeviceHealthSerializer(row).data, status=status.HTTP_200_OK)
