from django.urls import reverse

from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyMembership

from .models import Budget


class BudgetSyncTests(ApiTestCase):
    def setUp(self):
        self.owner = self.create_user("09120000001", full_name="مدیر")
        self.family = self.create_family_with(self.owner)
        self.member = self.create_user("09120000002", full_name="عضو")
        FamilyMembership.objects.create(
            family=self.family, user=self.member, role=FamilyMembership.Role.MEMBER
        )

    def _push(self, budgets):
        return self.client.post(reverse("budget-sync"), {"budgets": budgets}, format="json")

    def _budget(self, bid, name="میوه", limit=5000000, deleted=False):
        return {
            "id": bid,
            "category_name": name,
            "period": "monthly",
            "limit_rial": limit,
            "is_deleted": deleted,
            "client_updated_at": "2026-09-10T08:00:00Z",
        }

    def test_push_and_pull(self):
        self.auth(self.owner)
        bid = "11111111-1111-1111-1111-111111111111"
        r = self._push([self._budget(bid)])
        self.assertEqual(r.status_code, 200, r.data)
        pull = self.client.get(reverse("budget-sync"))
        self.assertEqual(len(pull.data["results"]), 1)
        self.assertEqual(pull.data["results"][0]["category_name"], "میوه")
        self.assertEqual(pull.data["results"][0]["limit_rial"], 5000000)

    def test_upsert_idempotent(self):
        self.auth(self.owner)
        bid = "22222222-2222-2222-2222-222222222222"
        self._push([self._budget(bid, limit=1000)])
        self._push([self._budget(bid, limit=2000)])
        self.assertEqual(Budget.objects.filter(id=bid).count(), 1)
        self.assertEqual(Budget.objects.get(id=bid).limit_rial, 2000)

    def test_budgets_are_family_shared(self):
        # عضو هم بودجه‌های خانواده را می‌بیند (بودجه هدفِ مشترک است)
        self.auth(self.owner)
        self._push([self._budget("33333333-3333-3333-3333-333333333333", name="قبوض")])
        self.auth(self.member)
        pull = self.client.get(reverse("budget-sync"))
        self.assertIn("قبوض", [b["category_name"] for b in pull.data["results"]])

    def test_soft_delete(self):
        self.auth(self.owner)
        bid = "44444444-4444-4444-4444-444444444444"
        self._push([self._budget(bid)])
        self._push([self._budget(bid, deleted=True)])
        pull = self.client.get(reverse("budget-sync"))
        self.assertTrue(pull.data["results"][0]["is_deleted"])
