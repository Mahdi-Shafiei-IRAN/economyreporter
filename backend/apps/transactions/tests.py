import uuid

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.test import TestCase

from apps.accounts.models import BankAccount, Card
from apps.categories.models import Category
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
        a = self._tx(kind=Transaction.Kind.TRANSFER, transfer_group=group)
        b = self._tx(kind=Transaction.Kind.TRANSFER, transfer_group=group)
        self.assertEqual(a.transfer_group, b.transfer_group)
        self.assertEqual(
            Transaction.objects.filter(transfer_group=group).count(), 2
        )
