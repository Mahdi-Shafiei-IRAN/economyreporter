from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .phone import normalize_phone, validate_mobile

User = get_user_model()


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "phone", "full_name", "created_at"]
        read_only_fields = fields


class PhonePasswordSerializer(serializers.Serializer):
    """ورودیِ مشترکِ ساختِ حساب: شماره + رمز + نام."""

    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(write_only=True, min_length=4, max_length=128)
    full_name = serializers.CharField(max_length=150, required=False, allow_blank=True)

    def validate_phone(self, value):
        phone = normalize_phone(value)
        validate_mobile(phone)  # شکل درست موبایل ایران
        if User.objects.filter(phone=phone).exists():
            raise serializers.ValidationError("کاربری با این شماره از قبل هست.")
        return phone

    def validate_password(self, value):
        validate_password(value)
        return value

    def create_user(self):
        data = self.validated_data
        return User.objects.create_user(
            phone=data["phone"],
            password=data["password"],
            full_name=data.get("full_name", ""),
        )


class RegisterSerializer(PhonePasswordSerializer):
    """ثبت‌نامِ آزاد: حساب + خانواده‌ی جدید (کاربر = مالک)."""

    family_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
