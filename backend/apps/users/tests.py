from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.urls import reverse
from rest_framework.test import APITestCase

User = get_user_model()


class AuthTests(APITestCase):
    def setUp(self):
        cache.clear()  # سطل throttle را بین تست‌ها ایزوله کن

    def test_register_creates_user(self):
        resp = self.client.post(
            reverse("auth-register"),
            {"email": "a@x.com", "full_name": "Ali", "password": "StrongPass123"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201)
        self.assertIn("id", resp.data)
        self.assertNotIn("password", resp.data)
        self.assertTrue(User.objects.filter(email="a@x.com").exists())

    def test_register_weak_password_rejected(self):
        resp = self.client.post(
            reverse("auth-register"),
            {"email": "b@x.com", "password": "123"},
            format="json",
        )
        self.assertEqual(resp.status_code, 400)

    def test_login_returns_tokens(self):
        User.objects.create_user(email="c@x.com", password="StrongPass123")
        resp = self.client.post(
            reverse("auth-login"),
            {"email": "c@x.com", "password": "StrongPass123"},
            format="json",
        )
        self.assertEqual(resp.status_code, 200)
        self.assertIn("access", resp.data)
        self.assertIn("refresh", resp.data)

    def test_me_requires_auth(self):
        resp = self.client.get(reverse("auth-me"))
        self.assertEqual(resp.status_code, 401)

    def test_me_returns_current_user(self):
        User.objects.create_user(
            email="d@x.com", password="StrongPass123", full_name="Dana"
        )
        login = self.client.post(
            reverse("auth-login"),
            {"email": "d@x.com", "password": "StrongPass123"},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        resp = self.client.get(reverse("auth-me"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.data["email"], "d@x.com")
        self.assertEqual(resp.data["full_name"], "Dana")


class AuthThrottleTests(APITestCase):
    def setUp(self):
        cache.clear()  # سطل throttle را برای تعیّن‌پذیری خالی کن

    def test_login_is_rate_limited(self):
        User.objects.create_user(email="t@x.com", password="StrongPass123")
        payload = {"email": "t@x.com", "password": "StrongPass123"}
        url = reverse("auth-login")

        rate = settings.REST_FRAMEWORK["DEFAULT_THROTTLE_RATES"]["auth"]
        allowed = int(rate.split("/")[0])

        for _ in range(allowed):
            resp = self.client.post(url, payload, format="json")
            self.assertEqual(resp.status_code, 200)

        # درخواست بعدی از سقف عبور می‌کند → محدود می‌شود
        blocked = self.client.post(url, payload, format="json")
        self.assertEqual(blocked.status_code, 429)
