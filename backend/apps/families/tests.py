from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework.test import APITestCase

from .models import FamilyMembership

User = get_user_model()

PWD = "StrongPass123"


class FamilyTests(APITestCase):
    def setUp(self):
        self.owner = User.objects.create_user(email="owner@x.com", password=PWD)
        self.member = User.objects.create_user(email="member@x.com", password=PWD)
        self.outsider = User.objects.create_user(email="out@x.com", password=PWD)

    def auth(self, user):
        login = self.client.post(
            reverse("auth-login"),
            {"email": user.email, "password": PWD},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")

    def create_family(self, user, name="خانواده"):
        self.auth(user)
        return self.client.post(
            reverse("family-list-create"), {"name": name}, format="json"
        )

    def invite(self, family_id, email):
        return self.client.post(
            reverse("family-invite", args=[family_id]), {"email": email}, format="json"
        )

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

    def test_owner_can_invite_existing_user(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        resp = self.invite(fid, "member@x.com")
        self.assertEqual(resp.status_code, 201)
        self.assertEqual(resp.data["role"], "member")
        self.assertEqual(resp.data["user"]["email"], "member@x.com")

    def test_invite_nonexistent_email_fails(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        resp = self.invite(fid, "ghost@x.com")
        self.assertEqual(resp.status_code, 400)

    def test_invite_beyond_max_fails(self):
        fid = self.create_family(self.owner).data["id"]
        User.objects.create_user(email="u2@x.com", password=PWD)
        User.objects.create_user(email="u3@x.com", password=PWD)
        self.auth(self.owner)
        self.invite(fid, "member@x.com")  # 2
        self.invite(fid, "u2@x.com")  # 3 (سقف)
        resp = self.invite(fid, "u3@x.com")  # 4 → رد
        self.assertEqual(resp.status_code, 400)

    def test_non_owner_cannot_invite(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        self.invite(fid, "member@x.com")
        self.auth(self.member)
        resp = self.invite(fid, "out@x.com")
        self.assertEqual(resp.status_code, 403)

    def test_outsider_cannot_view_members(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.outsider)
        resp = self.client.get(reverse("family-members", args=[fid]))
        self.assertEqual(resp.status_code, 404)  # وجود خانواده لو نمی‌رود

    def test_owner_can_remove_member(self):
        fid = self.create_family(self.owner).data["id"]
        self.auth(self.owner)
        mid = self.invite(fid, "member@x.com").data["id"]
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
