from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.urls import reverse
from rest_framework.test import APITestCase

from .models import FamilyMembership

User = get_user_model()

PWD = "StrongPass123"


class _FamilyBase(APITestCase):
    def setUp(self):
        cache.clear()  # سطل throttle auth را بین تست‌ها ایزوله کن
        self.owner = User.objects.create_user(phone="09120000001", password=PWD)
        self.member = User.objects.create_user(phone="09120000003", password=PWD)
        self.outsider = User.objects.create_user(phone="09120000002", password=PWD)

    def auth(self, user):
        login = self.client.post(
            reverse("auth-login"),
            {"phone": user.phone, "password": PWD},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    def create_family(self, user, name="خانواده"):
        self.auth(user)
        return self.client.post(
            reverse("family-list-create"), {"name": name}, format="json"
        )

    def invite(self, family_id, phone):
        return self.client.post(
            reverse("family-invite", args=[family_id]), {"phone": phone}, format="json"
        )



class FamilyTests(_FamilyBase):
    def test_create_family_makes_owner(self):
        resp = self.create_family(self.owner)
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data["my_role"], "owner")
        self.assertEqual(resp.data["member_count"], 1)
        self.assertTrue(
            FamilyMembership.objects.filter(
                family_id=resp.data["id"], user=self.owner, role="owner"
            ).exists()
        )

    def test_list_only_my_families(self):
        self.create_family(self.owner, "A")
        self.auth(self.outsider)
        resp = self.client.get(reverse("family-list-create"))
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(len(resp.data), 0)

    def test_owner_can_invite_existing_user_by_any_phone_format(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        resp = self.invite(fid, "+98 912 000 0003")
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data["role"], "member")
        self.assertEqual(resp.data["user"]["phone"], "09120000003")

    def test_invite_unknown_phone_without_password_fails(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        resp = self.invite(fid, "09129999999")
        self.assertEqual(resp.status_code, 400)

    def test_owner_creates_new_member_account_with_password(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        resp = self.client.post(
            reverse("family-invite", args=[fid]),
            {"phone": "09129999999", "password": "MemberPass1", "full_name": "پسر"},
            format="json",
        )
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertEqual(resp.data["user"]["phone"], "09129999999")
        # حسابِ تازه ساخته شد و می‌تواند وارد شود
        login = self.client.post(
            reverse("auth-login"),
            {"phone": "09129999999", "password": "MemberPass1"},
            format="json",
        )
        self.assertEqual(login.status_code, 200)

    def test_no_member_limit(self):
        """سقفِ اعضا برداشته شده؛ افزودنِ بیش از ۳ نفر هم باید کار کند."""
        fid = self.create_family(self.owner).data["id"]
        for i in range(4, 9):
            User.objects.create_user(phone=f"0912000000{i}", password=PWD)
        self.auth(self.owner)
        for i in range(4, 9):
            resp = self.invite(fid, f"0912000000{i}")
            self.assertEqual(resp.status_code, 201, resp.data)

    def test_non_owner_cannot_invite(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        self.invite(fid, "09120000003")
        self.auth(self.member)
        resp = self.invite(fid, "09120000002")
        self.assertEqual(resp.status_code, 403)

    def test_outsider_cannot_view_members(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.outsider)
        resp = self.client.get(reverse("family-members", args=[fid]))
        self.assertEqual(resp.status_code, 404)  # وجود خانواده لو نمی‌رود

    def test_owner_can_remove_member(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        mid = self.invite(fid, "09120000003").data["id"]
        resp = self.client.delete(reverse("family-membership-detail", args=[fid, mid]))
        self.assertEqual(resp.status_code, 204)
        self.assertFalse(FamilyMembership.objects.filter(id=mid).exists())

    def test_cannot_remove_last_owner(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        members = self.client.get(reverse("family-members", args=[fid])).data
        owner_mid = next(m["id"] for m in members if m["role"] == "owner")
        resp = self.client.delete(
            reverse("family-membership-detail", args=[fid, owner_mid])
        )
        self.assertEqual(resp.status_code, 400)


class DeviceHealthTests(_FamilyBase):
    """سلامتِ گوشی‌ها: هر گوشی گزارشِ خودش را می‌فرستد؛ مدیر گوشیِ همه‌ی اعضا را می‌بیند."""

    def report(self, device="dev-1", level="warn", **extra):
        return self.client.post(
            reverse("device-health"),
            {
                "device_id": device,
                "app_version": "1.0.22",
                "level": level,
                "summary": {"issues": [{"code": "deleted_valid", "count": 2}]},
                **extra,
            },
            format="json",
        )

    def setUp(self):
        super().setUp()
        fid = self.create_family(self.owner).data["id"]
        self.invite(fid, self.member.phone)

    def test_member_reports_and_owner_sees_it(self):
        self.auth(self.member)
        self.assertEqual(self.report().status_code, 200)
        # دوباره: همان ردیف به‌روز می‌شود، ردیفِ تازه ساخته نمی‌شود.
        self.assertEqual(self.report(level="ok").status_code, 200)

        self.auth(self.owner)
        rows = self.client.get(reverse("device-health")).data
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["level"], "ok")
        self.assertEqual(rows[0]["user"]["phone"], self.member.phone)
        self.assertEqual(rows[0]["app_version"], "1.0.22")

    def test_member_sees_only_own_devices(self):
        self.auth(self.owner)
        self.report(device="owner-phone")
        self.auth(self.member)
        self.report(device="member-phone")
        rows = self.client.get(reverse("device-health")).data
        self.assertEqual([r["device_id"] for r in rows], ["member-phone"])

    def test_outsider_sees_nothing_of_family(self):
        self.auth(self.member)
        self.report()
        self.auth(self.outsider)
        self.assertEqual(self.client.get(reverse("device-health")).data, [])

    def test_invalid_level_and_huge_summary_rejected(self):
        self.auth(self.member)
        self.assertEqual(self.report(level="great").status_code, 400)
        big = {"x": "a" * 40000}
        self.assertEqual(self.report(summary=big).status_code, 400)
        self.assertEqual(self.report(summary=[1, 2]).status_code, 400)

    def test_requires_auth(self):
        self.client.credentials()
        self.assertEqual(self.client.get(reverse("device-health")).status_code, 401)
