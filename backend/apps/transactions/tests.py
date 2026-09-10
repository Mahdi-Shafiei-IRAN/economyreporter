import uuid

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import BankAccount, Card
from apps.categories.models import Category
from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyGroup

from .models import Transaction

User = get_user_model()


class TransactionModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(email="a@x.com", password="StrongPass123")
        self.family = FamilyGroup.objects.create(name="خانواده")
        self.account = BankAccount.objects.create(
            family=self.family, owner=self.user, bank_name="بانک ملت", bank_id="mellat"
        )
        self.card = Card.objects.create(account=self.account, card_last4="1234")
        self.category = Category.objects.create(family=self.family, name="خوراک")

    def _tx(self, **kwargs):
        data = dict(
            family=self.family,
            owner=self.user,
            kind=Transaction.Kind.EXPENSE,
            amount_rial=2_500_000,
        )
        data.update(kwargs)
        return Transaction.objects.create(**data)

    def test_create_transaction_defaults(self):
        tx = self._tx(account=self.account, card=self.card, category=self.category)
        self.assertEqual(tx.source, Transaction.Source.SMS)
        self.assertEqual(tx.raw_unit, "rial")
        self.assertFalse(tx.needs_review)
        self.assertIsNotNone(tx.server_received_at)
        self.assertEqual(self.family.transactions.count(), 1)

    def test_duplicate_source_hash_rejected(self):
        self._tx(source_message_hash="abc123")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._tx(source_message_hash="abc123")

    def test_empty_hash_allows_multiple(self):
        self._tx(source_message_hash="")
        self._tx(source_message_hash="")
        self.assertEqual(Transaction.objects.filter(source_message_hash="").count(), 2)

    def test_category_set_null_on_delete(self):
        tx = self._tx(category=self.category)
        self.category.delete()
        tx.refresh_from_db()
        self.assertIsNone(tx.category)

    def test_transfer_group_link(self):
        group = uuid.uuid4()
        self._tx(kind=Transaction.Kind.TRANSFER, transfer_group=group)
        self._tx(kind=Transaction.Kind.TRANSFER, transfer_group=group)
        self.assertEqual(Transaction.objects.filter(transfer_group=group).count(), 2)


class TransactionApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("owner@x.com")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)

    def test_create_transaction_with_client_id(self):
        tid = str(uuid.uuid4())
        resp = self.client.post(
            reverse("transaction-list"),
            {"id": tid, "kind": "expense", "amount_rial": 2_000_000},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(str(resp.data["id"]), tid)
        self.assertEqual(str(resp.data["family"]), str(self.family.id))
        self.assertEqual(str(resp.data["owner"]), str(self.user.id))

    def test_list_isolated_between_families(self):
        Transaction.objects.create(
            family=self.family, owner=self.user, kind="expense", amount_rial=1000
        )
        outsider = self.create_user("out@x.com")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("transaction-list"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 0)

    def test_filter_by_kind(self):
        Transaction.objects.create(
            family=self.family, owner=self.user, kind="income", amount_rial=5000
        )
        Transaction.objects.create(
            family=self.family, owner=self.user, kind="expense", amount_rial=3000
        )
        resp = self.client.get(reverse("transaction-list"), {"kind": "income"})
        self.assertEqual(len(resp.data), 1)
        self.assertEqual(resp.data[0]["kind"], "income")


class SyncApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("owner@x.com")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)
        self.url = reverse("sync-transactions")

    def test_sync_creates_then_idempotent(self):
        items = [
            {"id": str(uuid.uuid4()), "kind": "expense", "amount_rial": 1000},
            {"id": str(uuid.uuid4()), "kind": "income", "amount_rial": 2000},
        ]
        payload = {"device_id": "dev1", "transactions": items}

        resp = self.client.post(self.url, payload, format="json")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual([r["status"] for r in resp.data["results"]], ["created", "created"])
        self.assertEqual(Transaction.objects.count(), 2)

        resp2 = self.client.post(self.url, payload, format="json")
        self.assertEqual(
            [r["status"] for r in resp2.data["results"]],
            ["already_exists", "already_exists"],
        )
        self.assertEqual(Transaction.objects.count(), 2)

    def test_sync_dedup_by_hash(self):
        a, b = str(uuid.uuid4()), str(uuid.uuid4())
        items = [
            {"id": a, "kind": "expense", "amount_rial": 1000, "source_message_hash": "h1"},
            {"id": b, "kind": "expense", "amount_rial": 1000, "source_message_hash": "h1"},
        ]
        resp = self.client.post(
            self.url, {"transactions": items}, format="json"
        )
        statuses = [r["status"] for r in resp.data["results"]]
        self.assertEqual(statuses, ["created", "already_exists"])
        # مورد دوم به id مورد اول اشاره می‌کند
        self.assertEqual(resp.data["results"][1]["id"], a)
        self.assertEqual(Transaction.objects.count(), 1)

    def test_sync_invalid_account_returns_error(self):
        items = [
            {
                "id": str(uuid.uuid4()),
                "kind": "expense",
                "amount_rial": 1000,
                "account": str(uuid.uuid4()),  # حساب نامعتبر
            }
        ]
        resp = self.client.post(self.url, {"transactions": items}, format="json")
        self.assertEqual(resp.data["results"][0]["status"], "error")
        self.assertEqual(Transaction.objects.count(), 0)


class DashboardApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("owner@x.com", full_name="علی")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)

    def _tx(self, kind, amount):
        return Transaction.objects.create(
            family=self.family, owner=self.user, kind=kind, amount_rial=amount
        )

    def test_summary_totals_exclude_transfer(self):
        self._tx("income", 10_000_000)
        self._tx("expense", 3_000_000)
        self._tx("transfer", 2_000_000)

        resp = self.client.get(reverse("dashboard-summary"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["family"]["income"], 10_000_000)
        self.assertEqual(resp.data["family"]["expenses"], 3_000_000)
        self.assertEqual(resp.data["family"]["balance"], 7_000_000)
        # تفکیک عضو و دسته موجود است
        self.assertEqual(resp.data["members"][0]["expenses"], 3_000_000)
        self.assertTrue(any(c["amount"] == 3_000_000 for c in resp.data["categories"]))
