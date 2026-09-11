from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse

from apps.categories.models import Category
from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyGroup

from .models import Budget


class BudgetModelTests(TestCase):
    def setUp(self):
        self.family = FamilyGroup.objects.create(name="خانواده")
        self.category = Category.objects.create(family=self.family, name="خوراک")

    def test_create_budget(self):
        b = Budget.objects.create(
            family=self.family, category=self.category, limit_rial=50_000_000
        )
        self.assertEqual(b.period, Budget.Period.MONTHLY)
        self.assertEqual(self.family.budgets.count(), 1)

    def test_duplicate_budget_per_category_period_rejected(self):
        Budget.objects.create(
            family=self.family, category=self.category, limit_rial=1000
        )
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Budget.objects.create(
                    family=self.family, category=self.category, limit_rial=2000
                )

    def test_different_period_ok(self):
        Budget.objects.create(
            family=self.family,
            category=self.category,
            period=Budget.Period.MONTHLY,
            limit_rial=1000,
        )
        Budget.objects.create(
            family=self.family,
            category=self.category,
            period=Budget.Period.WEEKLY,
            limit_rial=500,
        )
        self.assertEqual(Budget.objects.count(), 2)


class BudgetApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("09120000001")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)
        self.category = Category.objects.create(family=self.family, name="خوراک")

    def test_create_budget(self):
        resp = self.client.post(
            reverse("budget-list"),
            {"category": str(self.category.id), "limit_rial": 50_000_000},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(str(resp.data["family"]), str(self.family.id))

    def test_cannot_use_other_family_category(self):
        other_user = self.create_user("09120000002")
        other_fam = self.create_family_with(other_user, name="دیگر")
        other_cat = Category.objects.create(family=other_fam, name="حمل‌ونقل")
        resp = self.client.post(
            reverse("budget-list"),
            {"category": str(other_cat.id), "limit_rial": 1000},
            format="json",
        )
        self.assertEqual(resp.status_code, 404)
