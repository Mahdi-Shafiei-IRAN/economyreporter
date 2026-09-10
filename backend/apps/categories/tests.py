from django.db import IntegrityError, transaction
from django.test import TestCase

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
