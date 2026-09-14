from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APITestCase

from apps.families.models import FamilyGroup, FamilyMembership
from apps.transactions.models import Transaction

from .phone import normalize_phone

User = get_user_model()
PWD = "StrongPass123"


class PhoneNormalizeTests(TestCase):
    def test_variants_become_standard(self):
        for raw in [
            "09121234567",
            "+989121234567",
            "00989121234567",
            "989121234567",
            "9121234567",
            "۰۹۱۲۱۲۳۴۵۶۷",
            "0912 123 4567",
            "+98 (912) 123-4567",
        ]:
            self.assertEqual(normalize_phone(raw), "09121234567", raw)

    def test_non_mobile_is_left_for_validation(self):
        self.assertEqual(normalize_phone("abc"), "abc")
        self.assertEqual(normalize_phone(None), "")


class AuthTests(APITestCase):
    def setUp(self):
        cache.clear()  # سطل throttle را بین تست‌ها ایزوله کن

    def login(self, phone, password=PWD):
        return self.client.post(
            reverse("auth-login"), {"phone": phone, "password": password}, format="json"
        )

    def test_login_with_phone_returns_tokens(self):
        User.objects.create_user(phone="09121234567", password=PWD)
        resp = self.login("09121234567")
        self.assertEqual(resp.status_code, 200)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)

    def test_login_accepts_any_phone_format(self):
        User.objects.create_user(phone="+98 912 123 4567", password=PWD)
        self.assertEqual(User.objects.get().phone, "09121234567")
        for variant in ["۰۹۱۲۱۲۳۴۵۶۷", "+989121234567", "9121234567"]:
            self.assertEqual(self.login(variant).status_code, 200, variant)

    def test_wrong_password_rejected(self):
        User.objects.create_user(phone="09121234567", password=PWD)
        self.assertEqual(self.login("09121234567", "wrong-pass").status_code, 401)

    def test_email_login_no_longer_accepted(self):
        User.objects.create_user(phone="09121234567", password=PWD, email="a@x.com")
        resp = self.client.post(
            reverse("auth-login"), {"email": "a@x.com", "password": PWD}, format="json"
        )
        self.assertEqual(resp.status_code, 400)

    def test_inactive_user_cannot_login(self):
        User.objects.create_user(phone="09121234567", password=PWD, is_active=False)
        self.assertEqual(self.login("09121234567").status_code, 401)

    def test_register_creates_user_family_and_tokens(self):
        resp = self.client.post(
            reverse("auth-register"),
            {"phone": "۰۹۱۲۱۲۳۴۵۶۷", "password": PWD, "full_name": "بابا"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertIn("access", resp.data)
        user = User.objects.get()
        self.assertEqual(user.phone, "09121234567")
        # سازنده مالکِ خانواده‌ی تازه است
        membership = FamilyMembership.objects.get(user=user)
        self.assertEqual(membership.role, FamilyMembership.Role.OWNER)

    def test_register_rejects_duplicate_phone(self):
        User.objects.create_user(phone="09121234567", password=PWD)
        resp = self.client.post(
            reverse("auth-register"),
            {"phone": "09121234567", "password": PWD},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)
        self.assertEqual(User.objects.count(), 1)

    def test_me_requires_auth(self):
        resp = self.client.get(reverse("auth-me"))
        self.assertEqual(resp.status_code, 401)

    def test_me_returns_phone_and_name(self):
        User.objects.create_user(phone="09121234567", password=PWD, full_name="بابا")
        token = self.login("09121234567").data["access"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        resp = self.client.get(reverse("auth-me"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["phone"], "09121234567")
        self.assertEqual(resp.data["full_name"], "بابا")
        self.assertNotIn("email", resp.data)


class AuthThrottleTests(APITestCase):
    def setUp(self):
        cache.clear()  # سطل throttle را برای تعیّن‌پذیری خالی کن

    def test_login_is_rate_limited(self):
        User.objects.create_user(phone="09121234567", password=PWD)
        payload = {"phone": "09121234567", "password": PWD}
        url = reverse("auth-login")

        rate = settings.REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]["auth"]
        allowed = int(rate.split("/")[0])

        for _ in range(allowed):
            resp = self.client.post(url, payload, format="json")
            self.assertEqual(resp.status_code, 200)

        # درخواست بعدی از سقف عبور می‌کند → محدود می‌شود
        blocked = self.client.post(url, payload, format="json")
        self.assertEqual(blocked.status_code, 429)


class AdminPanelTests(TestCase):
    """همان کارهایی که مدیر در پنل می‌کند: ساخت کاربر با شماره/رمز و خانواده."""

    def setUp(self):
        cache.clear()
        self.admin = User.objects.create_superuser(phone="09120000000", password=PWD)
        self.client.force_login(self.admin)
        self.family = FamilyGroup.objects.create(name="خانواده")

    def _add_user(self, phone, name, family=None, password="Baba@12345"):
        return self.client.post(
            reverse("admin:users_user_add"),
            {
                "phone": phone,
                "full_name": name,
                "password1": password,
                "password2": password,
                "family_memberships-TOTAL_FORMS": "1",
                "family_memberships-INITIAL_FORMS": "0",
                "family_memberships-MIN_NUM_FORMS": "0",
                "family_memberships-MAX_NUM_FORMS": "1",
                "family_memberships-0-family": str(family.id) if family else "",
                "family_memberships-0-role": "member",
            },
        )

    def test_admin_pages_load(self):
        for name in [
            "admin:index",
            "admin:users_user_changelist",
            "admin:users_user_add",
            "admin:families_familygroup_changelist",
            "admin:families_familygroup_add",
            "admin:transactions_transaction_changelist",
            "admin:accounts_bankaccount_changelist",
            "admin:categories_category_changelist",
            "admin:budgets_budget_changelist",
        ]:
            self.assertEqual(self.client.get(reverse(name)).status_code, 200, name)

    def test_create_user_with_phone_password_and_family_then_login(self):
        resp = self._add_user("+98 912 555 1234", "بابا", self.family)
        self.assertEqual(resp.status_code, 302)
        user = User.objects.get(phone="09125551234")
        self.assertEqual(user.full_name, "بابا")
        self.assertTrue(
            FamilyMembership.objects.filter(user=user, family=self.family).exists()
        )
        # همان شماره و رمز در اپ کار می‌کند
        login = self.client.post(
            reverse("auth-login"),
            {"phone": "09125551234", "password": "Baba@12345"},
            content_type="application/json",
        )
        self.assertEqual(login.status_code, 200)

    def test_invalid_phone_rejected(self):
        resp = self._add_user("12345", "نامعتبر")
        self.assertEqual(resp.status_code, 200)  # فرم با خطا دوباره نشان داده می‌شود
        self.assertFalse(User.objects.filter(full_name="نامعتبر").exists())

    def test_duplicate_phone_rejected(self):
        User.objects.create_user(phone="09125551234", password=PWD)
        resp = self._add_user("۰۹۱۲۵۵۵۱۲۳۴", "دوباره")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(User.objects.filter(phone="09125551234").count(), 1)

    def test_soft_delete_action_reaches_phones(self):
        member = User.objects.create_user(phone="09125551234", password=PWD)
        tx = Transaction.objects.create(
            family=self.family, owner=member, kind="expense", amount_rial=1000
        )
        # ساعت ویندوز برای دو فراخوانی پشت‌سرهم یک زمان می‌دهد؛ ردیف را قدیمی کن.
        before = tx.updated_at.replace(year=2000)
        Transaction.objects.filter(pk=tx.pk).update(updated_at=before)
        resp = self.client.post(
            reverse("admin:transactions_transaction_changelist"),
            {"action": "mark_invalid", "_selected_action": [str(tx.id)]},
        )
        self.assertEqual(resp.status_code, 302)
        tx.refresh_from_db()
        self.assertTrue(tx.is_deleted)
        # updated_at جلو می‌رود تا گوشی‌ها در همگام‌سازی بعدی حذف را بگیرند
        self.assertGreater(tx.updated_at, before)

    def test_old_email_user_without_phone_can_be_deleted(self):
        legacy = User.objects.create(full_name="کاربر تست", email="test@economy.local")
        FamilyMembership.objects.create(family=self.family, user=legacy)
        Transaction.objects.create(
            family=self.family, owner=legacy, kind="expense", amount_rial=1000
        )
        self.assertContains(
            self.client.get(reverse("admin:users_user_changelist")), "کاربر تست"
        )
        resp = self.client.post(
            reverse("admin:users_user_delete", args=[legacy.pk]), {"post": "yes"}
        )
        self.assertEqual(resp.status_code, 302)
        self.assertFalse(User.objects.filter(pk=legacy.pk).exists())
        self.assertFalse(Transaction.objects.exists())
