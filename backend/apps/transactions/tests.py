import uuid

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import BankAccount, Card
from apps.categories.models import Category
from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyGroup, FamilyMembership

from .models import Transaction

User = get_user_model()


class TransactionModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(phone="09120000010", password="StrongPass123")
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
        self.user = self.create_user("09120000001")
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
        outsider = self.create_user("09120000002")
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
        self.user = self.create_user("09120000001")
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

    def test_one_crashing_item_does_not_fail_the_batch(self):
        """خطای پیش‌بینی‌نشده در یک آیتم → فقط همان «error»؛ بقیه ثبت (نه ۵۰۰ برای همه)."""
        from unittest import mock

        from .views import SyncView as TransactionSyncView

        bad = str(uuid.uuid4())
        good = str(uuid.uuid4())
        real = TransactionSyncView._process_item

        def crash_on_bad(view, item, ctx):
            if item.get("id") == bad:
                raise RuntimeError("boom")
            return real(view, item, ctx)

        with mock.patch.object(TransactionSyncView, "_process_item", crash_on_bad):
            resp = self.client.post(
                self.url,
                {"device_id": "d", "transactions": [
                    {"id": bad, "kind": "expense", "amount_rial": 1},
                    {"id": good, "kind": "income", "amount_rial": 2},
                ]},
                format="json",
            )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual([r["status"] for r in resp.data["results"]], ["error", "created"])
        self.assertTrue(Transaction.objects.filter(id=good).exists())

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
        self.user = self.create_user("09120000001", full_name="علی")
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

    def test_summary_excludes_deleted_and_uses_allocations(self):
        tx = self._tx("expense", 1_000_000)
        tx.allocations = [
            {"name": "میوه", "amount_rial": 600_000},
            {"name": "نان", "amount_rial": 400_000},
        ]
        tx.save()
        deleted = self._tx("expense", 9_000_000)
        deleted.is_deleted = True
        deleted.save()

        resp = self.client.get(reverse("dashboard-summary"))
        self.assertEqual(resp.data["family"]["expenses"], 1_000_000)
        by_name = {c["name"]: c["amount"] for c in resp.data["categories"]}
        self.assertEqual(by_name, {"میوه": 600_000, "نان": 400_000})


class SyncOwnershipTests(ApiTestCase):
    """مالکیت کارت، ویرایش فقط توسط صاحب، و دریافت تغییرات (pull)."""

    def setUp(self):
        self.me = self.create_user("09120000011", full_name="مهدی")
        self.family = self.create_family_with(self.me)
        self.father = self.create_user("09120000012", full_name="بابا")
        self.mother = self.create_user("09120000013", full_name="مامان")
        for u in (self.father, self.mother):
            FamilyMembership.objects.create(
                family=self.family, user=u, role=FamilyMembership.Role.MEMBER
            )
        self.outsider = self.create_user("09120000002")
        self.url = reverse("sync-transactions")

    def _push(self, user, *items):
        self.auth(user)
        resp = self.client.post(self.url, {"transactions": list(items)}, format="json")
        self.assertEqual(resp.status_code, 200)
        return resp.data["results"]

    def _item(self, **extra):
        data = {
            "id": str(uuid.uuid4()),
            "kind": "expense",
            "amount_rial": 1000,
            "client_updated_at": "2026-09-10T10:00:00Z",
        }
        data.update(extra)
        return data

    def test_null_text_fields_are_accepted(self):
        # همان payloadی که گوشی می‌فرستاد و قبلاً «may not be null» می‌گرفت
        item = self._item(counterparty=None, raw_amount=None, description=None)
        results = self._push(self.me, item)
        self.assertEqual(results[0]["status"], "created")
        tx = Transaction.objects.get(id=item["id"])
        self.assertEqual(tx.counterparty, "")
        self.assertEqual(tx.raw_amount, "")

    def test_owner_member_sets_owner_and_capturer(self):
        item = self._item(
            owner_member=str(self.father.id), person_name="بابا", wallet_label="کارت حقوق",
            card_last4="1234",
        )
        self._push(self.me, item)
        tx = Transaction.objects.get(id=item["id"])
        self.assertEqual(tx.owner, self.father)
        self.assertEqual(tx.captured_by, self.me)
        self.assertEqual(tx.card_last4, "1234")

    def test_owner_member_outside_family_falls_back_to_capturer(self):
        item = self._item(owner_member=str(self.outsider.id))
        self._push(self.me, item)
        self.assertEqual(Transaction.objects.get(id=item["id"]).owner, self.me)

    def test_newer_client_version_updates_and_same_version_is_idempotent(self):
        item = self._item(description="")
        self._push(self.me, item)

        newer = dict(item, description="نان", client_updated_at="2026-09-10T11:00:00Z")
        self.assertEqual(self._push(self.me, newer)[0]["status"], "updated")
        self.assertEqual(Transaction.objects.get(id=item["id"]).description, "نان")

        # همان نسخه دوباره → تغییری نمی‌کند
        self.assertEqual(self._push(self.me, newer)[0]["status"], "already_exists")
        # نسخه‌ی قدیمی‌تر → نادیده
        older = dict(item, description="قدیمی", client_updated_at="2026-09-10T10:30:00Z")
        self.assertEqual(self._push(self.me, older)[0]["status"], "already_exists")
        self.assertEqual(Transaction.objects.get(id=item["id"]).description, "نان")

    def test_capturer_changes_attribution_but_only_owner_changes_content(self):
        item = self._item(owner_member=str(self.father.id), person_name="بابا")
        self._push(self.me, item)

        # گوشی دریافت‌کننده (من) محتوا را عوض می‌کند → نادیده؛ انتساب → اعمال
        mine = dict(
            item, description="دست من", wallet_label="کارت جدید",
            client_updated_at="2026-09-10T11:00:00Z",
        )
        self.assertEqual(self._push(self.me, mine)[0]["status"], "updated")
        tx = Transaction.objects.get(id=item["id"])
        self.assertEqual(tx.description, "")
        self.assertEqual(tx.wallet_label, "کارت جدید")

        # صاحب کارت (بابا) دسته‌بندی و توضیح می‌دهد → اعمال
        fathers = dict(
            item, description="خرید میوه",
            allocations=[{"name": "میوه", "amount_rial": 1000}],
            client_updated_at="2026-09-10T12:00:00Z",
        )
        self.assertEqual(self._push(self.father, fathers)[0]["status"], "updated")
        tx.refresh_from_db()
        self.assertEqual(tx.description, "خرید میوه")
        self.assertEqual(tx.allocations, [{"name": "میوه", "amount_rial": 1000}])

    def test_other_member_cannot_edit(self):
        item = self._item(owner_member=str(self.father.id))
        self._push(self.me, item)
        hers = dict(item, description="نه", client_updated_at="2026-09-10T11:00:00Z")
        self.assertEqual(self._push(self.mother, hers)[0]["status"], "forbidden")
        self.assertEqual(Transaction.objects.get(id=item["id"]).description, "")

    def test_owner_can_soft_delete_and_it_is_pulled(self):
        item = self._item(owner_member=str(self.father.id))
        self._push(self.me, item)
        gone = dict(item, is_deleted=True, client_updated_at="2026-09-10T11:00:00Z")
        self.assertEqual(self._push(self.father, gone)[0]["status"], "updated")

        # مدیر خانواده (me) حذف را در دریافت می‌بیند؛ صاحبش (بابا) هم.
        self.auth(self.me)
        resp = self.client.get(self.url)
        row = next(r for r in resp.data["results"] if r["id"] == item["id"])
        self.assertTrue(row["is_deleted"])

    def test_pull_returns_changes_since_cursor(self):
        a, b = self._item(), self._item(owner_member=str(self.father.id), person_name="بابا")
        self._push(self.me, a, b)

        # مدیر خانواده کلِ خانواده را می‌بیند (cursor/delta روی همه).
        self.auth(self.me)
        first = self.client.get(self.url).data
        self.assertEqual({r["id"] for r in first["results"]}, {a["id"], b["id"]})
        names = {r["id"]: r["owner_name"] for r in first["results"]}
        self.assertEqual(names[b["id"]], "بابا")
        self.assertEqual(names[a["id"]], "مهدی")
        self.assertFalse(first["has_more"])

        # بدون تغییر → چیزی برنمی‌گردد
        empty = self.client.get(self.url, {"since": first["cursor"]}).data
        self.assertEqual(empty["results"], [])

        # یک تغییر → فقط همان
        self._push(self.me, dict(a, description="x", client_updated_at="2026-09-10T11:00:00Z"))
        self.auth(self.me)
        delta = self.client.get(self.url, {"since": first["cursor"]}).data
        self.assertEqual([r["id"] for r in delta["results"]], [a["id"]])

    def test_pull_paginates_with_has_more(self):
        self._push(self.me, *[self._item() for _ in range(3)])
        page = self.client.get(self.url, {"limit": 2}).data
        self.assertEqual(len(page["results"]), 2)
        self.assertTrue(page["has_more"])
        rest = self.client.get(self.url, {"since": page["cursor"], "limit": 2}).data
        self.assertEqual(len(rest["results"]), 1)
        self.assertFalse(rest["has_more"])

    def test_pull_does_not_lose_rows_with_equal_updated_at(self):
        # عملیات گروهی (مثلاً «نامعتبر کن» در پنل) به چند ردیف یک updated_at می‌دهد؛
        # مرز صفحه نباید ردیف‌های هم‌زمان را جا بیندازد.
        items = [self._item() for _ in range(5)]
        self._push(self.me, *items)
        Transaction.objects.update(updated_at=Transaction.objects.first().updated_at)
        seen, cursor = [], None
        for _ in range(10):
            params = {"limit": 2, **({"since": cursor} if cursor else {})}
            page = self.client.get(self.url, params).data
            seen += [r["id"] for r in page["results"]]
            cursor = page["cursor"]
            if not page["has_more"]:
                break
        self.assertEqual(sorted(seen), sorted(i["id"] for i in items))

    def test_pull_accepts_old_time_only_cursor(self):
        a = self._item()
        self._push(self.me, a)
        resp = self.client.get(self.url, {"since": "2000-01-01T00:00:00Z"})
        self.assertEqual([r["id"] for r in resp.data["results"]], [a["id"]])

    def test_member_pulls_only_own_manager_pulls_all(self):
        # me = مالک (مدیر)، father و mother = عضو عادی
        a = self._item(owner_member=str(self.father.id))  # مالِ بابا
        b = self._item()  # مالِ me (پیش‌فرض)
        self._push(self.me, a, b)
        c = self._item()
        self._push(self.mother, c)  # مالِ مامان

        # عضو عادی (مامان): فقط مالِ خودش
        self.auth(self.mother)
        ids = {r["id"] for r in self.client.get(self.url).data["results"]}
        self.assertEqual(ids, {c["id"]})

        # عضو عادی (بابا): فقط مالِ خودش (که me برایش ثبت کرد)
        self.auth(self.father)
        ids = {r["id"] for r in self.client.get(self.url).data["results"]}
        self.assertEqual(ids, {a["id"]})

        # مدیر خانواده (me): همه‌ی خانواده
        self.auth(self.me)
        ids = {r["id"] for r in self.client.get(self.url).data["results"]}
        self.assertEqual(ids, {a["id"], b["id"], c["id"]})

    def test_superuser_pulls_all(self):
        a = self._item(owner_member=str(self.father.id))
        self._push(self.me, a)
        boss = User.objects.create_superuser(phone="09129999999", password="StrongPass123")
        FamilyMembership.objects.create(
            family=self.family, user=boss, role=FamilyMembership.Role.MEMBER
        )
        self.auth(boss)  # عضو عادیِ خانواده ولی ادمین کل → همه را می‌بیند
        ids = {r["id"] for r in self.client.get(self.url).data["results"]}
        self.assertEqual(ids, {a["id"]})

    def test_rest_list_scoped_by_role(self):
        a = self._item(owner_member=str(self.father.id))
        b = self._item()  # مالِ me
        self._push(self.me, a, b)

        # عضو عادی (بابا) در REST هم فقط مالِ خودش
        self.auth(self.father)
        ids = {str(r["id"]) for r in self.client.get(reverse("transaction-list")).data}
        self.assertEqual(ids, {a["id"]})

        # مدیر (me) همه
        self.auth(self.me)
        ids = {str(r["id"]) for r in self.client.get(reverse("transaction-list")).data}
        self.assertEqual(ids, {a["id"], b["id"]})

    def test_pull_is_isolated_between_families(self):
        self._push(self.me, self._item())
        self.create_family_with(self.outsider)
        self.auth(self.outsider)
        self.assertEqual(self.client.get(self.url).data["results"], [])

    def test_rest_update_and_delete_only_by_owner(self):
        item = self._item(owner_member=str(self.father.id))
        self._push(self.me, item)
        detail = reverse("transaction-detail", args=[item["id"]])

        # مامان (عضو عادی) اصلاً این تراکنش را نمی‌بیند → ۴۰۴ (حتی از وجودش باخبر نمی‌شود).
        self.auth(self.mother)
        resp = self.client.patch(detail, {"description": "x"}, format="json")
        self.assertEqual(resp.status_code, 404)

        self.auth(self.father)
        resp = self.client.patch(detail, {"description": "ok"}, format="json")
        self.assertEqual(resp.status_code, 200)
        resp = self.client.delete(detail)
        self.assertEqual(resp.status_code, 204)
        self.assertTrue(Transaction.objects.get(id=item["id"]).is_deleted)
