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
        self.user = User.objects.create_user(email="a@x.com", password="StrongPass123")
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
        self.user = self.create_user("owner@x.com")
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
        outsider = self.create_user("out@x.com")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("account-list"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 0)

    def test_cannot_retrieve_other_family_account(self):
        acc = BankAccount.objects.create(
            family=self.family, owner=self.user, bank_name="ملت"
        )
        outsider = self.create_user("out@x.com")
        self.create_family_with(outsider, name="دیگر")
        self.auth(outsider)
        resp = self.client.get(reverse("account-detail", args=[acc.id]))
        self.assertEqual(resp.status_code, 404)


class CardApiTests(ApiTestCase):
    def setUp(self):
        self.user = self.create_user("owner@x.com")
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
        other_user = self.create_user("x2@x.com")
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
