"""ابزار مشترک تست API."""

from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from apps.families.models import FamilyGroup, FamilyMembership

User = get_user_model()
PWD = "StrongPass123"


class ApiTestCase(APITestCase):
    def create_user(self, phone, **extra):
        return User.objects.create_user(phone=phone, password=PWD, **extra)

    def create_family_with(self, user, name="خانواده", role=FamilyMembership.Role.OWNER):
        family = FamilyGroup.objects.create(name=name)
        FamilyMembership.objects.create(family=family, user=user, role=role)
        return family

    def auth(self, user):
        self.client.force_authenticate(user=user)
