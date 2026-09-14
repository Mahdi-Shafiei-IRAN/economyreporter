from django.contrib.auth import get_user_model
from django.shortcuts import get_object_or_404
from rest_framework import generics, status
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.users.phone import normalize_phone

from .models import FamilyGroup, FamilyMembership
from .permissions import is_member, is_owner
from .serializers import (
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
