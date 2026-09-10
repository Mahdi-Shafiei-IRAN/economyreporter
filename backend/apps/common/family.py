"""تشخیص خانواده‌ی کاربر و محدودسازی داده به خانواده‌های او (ایزوله‌سازی)."""

from rest_framework.exceptions import NotFound, ValidationError

from apps.families.models import FamilyMembership


def user_family_ids(user):
    """شناسه‌ی همه‌ی خانواده‌هایی که کاربر عضو آن‌هاست."""
    return list(
        FamilyMembership.objects.filter(user=user).values_list("family_id", flat=True)
    )


def resolve_family(user, family_id=None):
    """
    خانواده‌ی هدف برای عملیات را برمی‌گرداند.

    - اگر family_id داده شود و کاربر عضو باشد → همان (وگرنه 404 تا وجودش لو نرود).
    - اگر داده نشود و کاربر دقیقاً یک خانواده داشته باشد → همان.
    - در غیر این صورت خطای اعتبارسنجی.
    """
    memberships = list(
        FamilyMembership.objects.filter(user=user).select_related("family")
    )
    if family_id:
        for m in memberships:
            if str(m.family_id) == str(family_id):
                return m.family
        raise NotFound()
    if len(memberships) == 1:
        return memberships[0].family
    if not memberships:
        raise ValidationError("شما عضو هیچ خانواده‌ای نیستید")
    raise ValidationError("چند خانواده دارید؛ پارامتر family را مشخص کنید")
