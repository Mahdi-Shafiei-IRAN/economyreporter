from rest_framework import serializers

from apps.users.phone import normalize_phone, validate_mobile
from apps.users.serializers import UserSerializer

from .models import FamilyGroup, FamilyMembership


class FamilyMembershipSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = FamilyMembership
        fields = ["id", "user", "role", "joined_at"]
        read_only_fields = fields


class FamilyGroupSerializer(serializers.ModelSerializer):
    my_role = serializers.SerializerMethodField()
    member_count = serializers.SerializerMethodField()

    class Meta:
        model = FamilyGroup
        fields = ["id", "name", "created_at", "my_role", "member_count"]
        read_only_fields = ["id", "created_at", "my_role", "member_count"]

    def get_my_role(self, obj):
        user = self.context["request"].user
        membership = obj.memberships.filter(user=user).first()
        return membership.role if membership else None

    def get_member_count(self, obj):
        return obj.memberships.count()


class InviteSerializer(serializers.Serializer):
    """افزودن عضو: اگر کاربر با این شماره باشد اضافه می‌شود؛ وگرنه با رمزِ داده‌شده
    حسابِ تازه ساخته می‌شود (ثبت‌نامِ آزاد)."""

    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(
        write_only=True, min_length=4, max_length=128, required=False, allow_blank=True
    )
    full_name = serializers.CharField(max_length=150, required=False, allow_blank=True)

    def validate_phone(self, value):
        phone = normalize_phone(value)
        validate_mobile(phone)
        return phone
