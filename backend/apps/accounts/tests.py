from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse

from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyGroup

from .models import BankAccount, Card

User = get_user_model()


class AccountModelTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(phone="09120000010", password="StrongPass123")
        self.family = FamilyGroup.objects.create(name="خانواده")

    def _account(self):
        return BankAccount.objects.create(
            family=self.family, owner=self.user, bank_name="بانک ملت", bank_id="mellat"
        )

    def test_create_account_and_card(self):
        acc = self._account()
        card = Card.objects.create(account=acc, card_last4="1234", card_label="اصلی")
        self.assertEqual(acc.currency, "IRR")
        self.assertTrue(acc.is_active)
        self.assertEqual(card.account, acc)
        self.assertEqual(acc.cards.count(), 1)

    def test_duplicate_card_per_account_rejected(self):
        acc = self._account()
        Card.objects.create(account=acc, card_last4="1234")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Card.objects.create(account=acc, card_last4="1234")

    def test_same_last4_different_account_ok(self):
        Card.objects.create(account=self._account(), card_last4="1234")
        Card.objects.create(account=self._account(), card_last4="1234")
        self.assertEqual(Card.objects.filter(card_last4="1234").count(), 2)


class AccountApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("09120000001")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)

    def test_create_account_sets_family_and_owner(self):
        resp = self.client.post(
            reverse("account-list"),
            {"bank_name": "بانک ملت", "bank_id": "mellat"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(str(resp.data["family"]), str(self.family.id))
        self.assertEqual(str(resp.data["owner"]), str(self.user.id))

    def test_list_scoped_to_family(self):
        BankAccount.objects.create(family=self.family, owner=self.user, bank_name="ملت")
        outsider = self.create_user("09120000002")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("account-list"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 0)

    def test_cannot_retrieve_other_family_account(self):
        acc = BankAccount.objects.create(
            family=self.family, owner=self.user, bank_name="ملت"
        )
        outsider = self.create_user("09120000002")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("account-detail", args=[acc.id]))
        self.assertEqual(resp.status_code, 404)


class CardApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("09120000001")
        self.family = self.create_family_with(self.user)
        self.auth(self.user)
        self.account = BankAccount.objects.create(
            family=self.family, owner=self.user, bank_name="ملت"
        )

    def test_create_card(self):
        resp = self.client.post(
            reverse("card-list"),
            {"account": str(self.account.id), "card_last4": "1234"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data["card_last4"], "1234")

    def test_cannot_attach_card_to_other_family_account(self):
        other_user = self.create_user("09120000003")
        other_fam = self.create_family_with(other_user, name="دیگر")
        other_acc = BankAccount.objects.create(
            family=other_fam, owner=other_user, bank_name="ملی"
        )
        resp = self.client.post(
            reverse("card-list"),
            {"account": str(other_acc.id), "card_last4": "9999"},
            format="json",
        )
        self.assertEqual(resp.status_code, 404)


class WalletSyncTests(ApiTestCase):
    def setUp(self):
        self.owner = self.create_user("09120000001", full_name="مدیر")
        self.family = self.create_family_with(self.owner)
        self.member = self.create_user("09120000002", full_name="عضو")
        from apps.families.models import FamilyMembership
        FamilyMembership.objects.create(
            family=self.family, user=self.member, role=FamilyMembership.Role.MEMBER
        )

    def _push(self, wallets):
        return self.client.post(
            reverse("wallet-sync"), {"wallets": wallets}, format="json"
        )

    def _wallet(self, wid, owner_user_id=None, label="کارت", deleted=False):
        return {
            "id": wid,
            "owner_user_id": owner_user_id,
            "owner_name": "مدیر",
            "label": label,
            "bank_id": "mellat",
            "card_last4": "1234",
            "account_ref": "",
            "is_deleted": deleted,
            "client_updated_at": "2026-09-10T08:00:00Z",
        }

    def test_push_creates_and_pull_returns(self):
        self.auth(self.owner)
        wid = "11111111-1111-1111-1111-111111111111"
        resp = self._push([self._wallet(wid, owner_user_id=str(self.owner.id))])
        self.assertEqual(resp.status_code, 200, resp.data)

        pull = self.client.get(reverse("wallet-sync"))
        self.assertEqual(pull.status_code, 200)
        self.assertEqual(len(pull.data["results"]), 1)
        self.assertEqual(pull.data["results"][0]["owner_user_id"], str(self.owner.id))
        self.assertIsNotNone(pull.data["cursor"])

    def test_upsert_is_idempotent(self):
        self.auth(self.owner)
        wid = "22222222-2222-2222-2222-222222222222"
        self._push([self._wallet(wid, label="اول")])
        self._push([self._wallet(wid, label="دوم")])
        from .models import Wallet
        self.assertEqual(Wallet.objects.filter(id=wid).count(), 1)
        self.assertEqual(Wallet.objects.get(id=wid).label, "دوم")

    def test_member_pull_only_sees_own(self):
        self.auth(self.owner)
        self._push([
            self._wallet("33333333-3333-3333-3333-333333333333",
                         owner_user_id=str(self.owner.id), label="مالِ مدیر"),
        ])
        self.auth(self.member)
        self._push([
            self._wallet("44444444-4444-4444-4444-444444444444",
                         owner_user_id=str(self.member.id), label="مالِ عضو"),
        ])
        pull = self.client.get(reverse("wallet-sync"))
        labels = [w["label"] for w in pull.data["results"]]
        self.assertIn("مالِ عضو", labels)
        self.assertNotIn("مالِ مدیر", labels)

    def test_manager_pull_sees_all(self):
        self.auth(self.member)
        self._push([
            self._wallet("55555555-5555-5555-5555-555555555555",
                         owner_user_id=str(self.member.id), label="مالِ عضو"),
        ])
        self.auth(self.owner)
        self._push([
            self._wallet("66666666-6666-6666-6666-666666666666",
                         owner_user_id=str(self.owner.id), label="مالِ مدیر"),
        ])
        pull = self.client.get(reverse("wallet-sync"))
        labels = {w["label"] for w in pull.data["results"]}
        self.assertEqual(labels, {"مالِ عضو", "مالِ مدیر"})

    def test_soft_delete_propagates(self):
        self.auth(self.owner)
        wid = "77777777-7777-7777-7777-777777777777"
        self._push([self._wallet(wid, owner_user_id=str(self.owner.id))])
        self._push([self._wallet(wid, owner_user_id=str(self.owner.id), deleted=True)])
        pull = self.client.get(reverse("wallet-sync"))
        self.assertTrue(pull.data["results"][0]["is_deleted"])
