from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase

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
