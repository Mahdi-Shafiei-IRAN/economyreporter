"""پنل مدیریت: ساخت کاربر با شماره موبایل + رمز و وصل کردنش به خانواده."""

from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from django.contrib.auth.forms import BaseUserCreationForm
from django.contrib.auth.forms import UserChangeForm as DjangoUserChangeForm
from django.contrib.auth.models import Group

from apps.families.models import FamilyMembership

from .models import User
from .phone import normalize_phone

admin.site.site_header = "پنل مدیریت مالی خانواده"
admin.site.site_title = "مالی خانواده"
admin.site.index_title = "کاربران، خانواده‌ها و داده‌ها"

# گروه و مجوزهای جزئی لازم نیست: مدیر همان superuser است.
admin.site.unregister(Group)


class PhoneFormField(forms.CharField):
    """«+98 912…» یا ارقام فارسی را قبل از اعتبارسنجی (مثل سقف ۱۱ رقم) استاندارد می‌کند."""

    def to_python(self, value):
        value = super().to_python(value)
        return value if value in self.empty_values else normalize_phone(value)


class UserCreationForm(BaseUserCreationForm):
    class Meta:
        model = User
        fields = ("phone", "full_name")
        field_classes = {"phone": PhoneFormField}


class UserChangeForm(DjangoUserChangeForm):
    class Meta:
        model = User
        fields = "__all__"
        field_classes = {"phone": PhoneFormField}


class MembershipInline(admin.TabularInline):
    model = FamilyMembership
    fk_name = "user"
    extra = 1
    max_num = 1
    fields = ("family", "role")
    verbose_name = "خانواده"
    verbose_name_plural = "خانواده‌ی این کاربر"


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    form = UserChangeForm
    add_form = UserCreationForm
    add_form_template = None
    inlines = [MembershipInline]

    fieldsets = (
        (None, {"fields": ("phone", "password")}),
        ("مشخصات", {"fields": ("full_name", "email")}),
        (
            "دسترسی",
            {
                "fields": ("is_active", "is_staff", "is_superuser"),
                "description": "برای اینکه کسی دیگر وارد نشود «فعال» را بردار (بهتر از حذف؛ "
                "تراکنش‌هایش می‌ماند). «کارمند» و «ابرکاربر» فقط برای کسی است که باید "
                "وارد همین پنل شود.",
            },
        ),
        ("تاریخ‌ها", {"fields": ("last_login", "date_joined")}),
    )
    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": ("phone", "full_name", "password1", "password2"),
                "description": "کاربر با همین شماره و رمز وارد اپ می‌شود. خانواده‌اش را "
                "پایین همین صفحه انتخاب کن.",
            },
        ),
    )
    readonly_fields = ("last_login", "date_joined")
    list_display = (
        "full_name",
        "phone",
        "family_names",
        "is_active",
        "is_superuser",
        "last_login",
    )
    list_display_links = ("full_name", "phone")
    list_filter = ("is_active", "is_superuser", "family_memberships__family")
    search_fields = ("phone", "full_name", "email")
    ordering = ("full_name", "phone")
    filter_horizontal = ()

    def get_queryset(self, request):
        return super().get_queryset(request).prefetch_related("family_memberships__family")

    @admin.display(description="خانواده")
    def family_names(self, obj):
        return "، ".join(m.family.name for m in obj.family_memberships.all()) or "—"
