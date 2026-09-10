"""کمک‌توابع Authorization سطح‌شیء برای خانواده."""

from .models import FamilyMembership


def is_member(user, family) -> bool:
    return FamilyMembership.objects.filter(family=family, user=user).exists()


def is_owner(user, family) -> bool:
    return FamilyMembership.objects.filter(
        family=family, user=user, role=FamilyMembership.Role.OWNER
    ).exists()
