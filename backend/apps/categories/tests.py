from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse

from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyGroup

from .models import Category


class CategoryModelTests(TestCase):
    def setUp(self):
        self.family = FamilyGroup.objects.create(name="خانواده")

    def test_create_category(self):
        cat = Category.objects.create(family=self.family, name="خوراک", color="#f00")
        self.assertFalse(cat.is_system)
        self.assertEqual(self.family.categories.count(), 1)

    def test_duplicate_name_per_family_rejected(self):
        Category.objects.create(family=self.family, name="خوراک")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Category.objects.create(family=self.family, name="خوراک")

    def test_same_name_different_family_ok(self):
        other = FamilyGroup.objects.create(name="خانواده دیگر")
        Category.objects.create(family=self.family, name="خوراک")
        Category.objects.create(family=other, name="خوراک")
        self.assertEqual(Category.objects.filter(name="خوراک").count(), 2)


class CategoryApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("09120000001")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)

    def test_create_category(self):
        resp = self.client.post(
            reverse("category-list"),
            {"name": "خوراک", "color": "#f00"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(str(resp.data["family"]), str(self.family.id))

    def test_list_scoped_to_family(self):
        Category.objects.create(family=self.family, name="خوراک")
        outsider = self.create_user("09120000002")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("category-list"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 0)
