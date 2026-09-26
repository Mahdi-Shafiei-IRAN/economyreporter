"""همگام‌سازیِ دفترِ نسخه‌ی ۲ (docs/v2-design.md ۱۲.۷)."""
import uuid

from django.utils.dateparse import parse_datetime

from apps.accounts.models import Wallet
from apps.common.testutils import ApiTestCase
from apps.families.models import FamilyMembership

from .models import LedgerEntry, SmsDecision

ENTRIES = "/api/v1/ledger/entries/sync/"
CHECKPOINTS = "/api/v1/ledger/checkpoints/sync/"
DECISIONS = "/api/v1/ledger/decisions/sync/"
SETTINGS = "/api/v1/ledger/settings/"


def entry(**over):
    base = {
        "id": str(uuid.uuid4()),
        "account_id": str(uuid.uuid4()),
        "kind": "expense",
        "is_transfer": False,
        "amount_rial": 100000,
        "occurred_at": "2026-09-23T07:00:00Z",
        "bank_balance_after": 900000,
        "source": "sms",
        "sms_key": "abc:1",
        "note": None,
        "categories": ["نان"],
        "created_by_device": "dev",
        "client_updated_at": "2026-09-23T07:01:00Z",
        "deleted_at": None,
    }
    return {**base, **over}


class LedgerSyncTests(ApiTestCase):
    def setUp(self):
        self.owner = self.create_user("09120000001", full_name="مدیر")
        self.family = self.create_family_with(self.owner)
        self.member = self.create_user("09120000002", full_name="عضو")
        FamilyMembership.objects.create(
            family=self.family, user=self.member, role=FamilyMembership.Role.MEMBER
        )
        self.auth(self.owner)

    def push(self, url, key, items):
        resp = self.client.post(url, {key: items}, format="json")
        self.assertEqual(resp.status_code, 200, resp.content)
        return resp.data["results"]

    def test_entries_upsert_is_idempotent_and_pulls_back(self):
        e = entry()
        self.assertEqual(self.push(ENTRIES, "entries", [e])[0]["status"], "created")
        self.assertEqual(self.push(ENTRIES, "entries", [e])[0]["status"], "updated")
        self.assertEqual(LedgerEntry.objects.count(), 1)

        page = self.client.get(ENTRIES).data
        self.assertEqual(len(page["results"]), 1)
        row = page["results"][0]
        self.assertEqual(row["categories"], ["نان"])
        self.assertEqual(row["note"], "")
        self.assertFalse(page["has_more"])
        # چیزی بعد از cursor نیست.
        self.assertEqual(self.client.get(ENTRIES, {"since": page["cursor"]}).data["results"], [])

    def test_a_bad_item_does_not_block_the_rest(self):
        results = self.push(ENTRIES, "entries", [entry(amount_rial=0), entry()])
        self.assertEqual([r["status"] for r in results], ["error", "created"])

    def test_older_client_version_is_stale_and_gets_the_server_copy(self):
        e = entry(note="جدید", client_updated_at="2026-09-23T08:00:00Z")
        self.push(ENTRIES, "entries", [e])
        old = {**e, "note": "قدیمی", "client_updated_at": "2026-09-23T07:30:00Z"}
        result = self.push(ENTRIES, "entries", [old])[0]
        self.assertEqual(result["status"], "stale")
        self.assertEqual(result["note"], "جدید")
        self.assertEqual(LedgerEntry.objects.get().note, "جدید")

    def test_phase4_each_user_sees_and_writes_only_their_own(self):
        e = entry()
        self.push(ENTRIES, "entries", [e])
        self.auth(self.member)
        self.assertEqual(self.client.get(ENTRIES).data["results"], [])
        results = self.push(ENTRIES, "entries", [{**e, "note": "دست‌کاری"}])
        self.assertEqual(results[0]["status"], "forbidden")
        self.assertEqual(LedgerEntry.objects.get().note, "")

    def test_another_familys_id_is_a_conflict(self):
        e = entry()
        self.push(ENTRIES, "entries", [e])
        stranger = self.create_user("09120000009")
        self.create_family_with(stranger, name="دیگری")
        self.auth(stranger)
        self.assertEqual(self.push(ENTRIES, "entries", [e])[0]["status"], "conflict")

    def test_checkpoints(self):
        cp = {
            "id": str(uuid.uuid4()),
            "account_id": str(uuid.uuid4()),
            "at": "2026-09-24T10:00:00Z",
            "balance_rial": 1200000,
            "note": None,
            "client_updated_at": "2026-09-24T10:00:00Z",
            "deleted_at": None,
        }
        self.assertEqual(self.push(CHECKPOINTS, "checkpoints", [cp])[0]["status"], "created")
        self.assertEqual(self.client.get(CHECKPOINTS).data["results"][0]["balance_rial"], 1200000)

    def test_decisions_have_no_sms_text_and_newer_decision_wins(self):
        d = {
            "key": "hash1:29830000",
            "content_hash": "hash1",
            "received_at": "2026-09-23T07:00:00Z",
            "status": "rejected",
            "reject_reason": "not_tx",
            "entry_id": None,
            "decided_at": "2026-09-23T09:00:00Z",
            # گوشی نباید بفرستد؛ اگر هم فرستاد جایی ذخیره نمی‌شود.
            "body": "حساب1000005596 برداشت",
            "sender": "Bank Mellat",
        }
        self.assertEqual(self.push(DECISIONS, "decisions", [d])[0]["status"], "created")
        field_names = {f.name for f in SmsDecision._meta.get_fields()}
        self.assertFalse({"body", "sender", "text"} & field_names)
        row = self.client.get(DECISIONS).data["results"][0]
        self.assertNotIn("body", row)
        self.assertNotIn("sender", row)

        older = {**d, "status": "accepted", "decided_at": "2026-09-23T08:00:00Z"}
        stale = self.push(DECISIONS, "decisions", [older])[0]
        self.assertEqual(stale["status"], "stale")
        self.assertEqual(stale["decision"]["status"], "rejected")
        newer = {**d, "status": "accepted", "entry_id": str(uuid.uuid4()), "decided_at": "2026-09-23T10:00:00Z"}
        self.assertEqual(self.push(DECISIONS, "decisions", [newer])[0]["status"], "updated")
        self.assertEqual(SmsDecision.objects.get().status, "accepted")

        self.auth(self.member)
        self.assertEqual(self.client.get(DECISIONS).data["results"], [])

    def test_settings_round_trip(self):
        self.assertEqual(self.client.get(SETTINGS).data["enabled"], False)
        resp = self.client.put(
            SETTINGS, {"enabled": True, "start_date": "2026-09-22T20:30:00Z"}, format="json"
        )
        self.assertEqual(resp.status_code, 200)
        data = self.client.get(SETTINGS).data
        self.assertTrue(data["enabled"])
        # سرور به وقتِ تهران برمی‌گرداند؛ همان لحظه است.
        self.assertEqual(parse_datetime(data["start_date"]), parse_datetime("2026-09-22T20:30:00Z"))
        self.assertFalse(data["setup_done"])

    def test_wallet_archived_round_trip_and_kept_when_old_clients_omit_it(self):
        wid = str(uuid.uuid4())
        w = {"id": wid, "owner_name": "مهدی", "label": "ملت", "bank_id": "mellat", "archived": True}
        self.client.post("/api/v1/wallets/sync/", {"wallets": [w]}, format="json")
        self.assertTrue(Wallet.objects.get(id=wid).archived)
        old_client = {k: v for k, v in w.items() if k != "archived"} | {"label": "ملت ۲"}
        self.client.post("/api/v1/wallets/sync/", {"wallets": [old_client]}, format="json")
        wallet = Wallet.objects.get(id=wid)
        self.assertTrue(wallet.archived)
        self.assertEqual(wallet.label, "ملت ۲")
        pulled = self.client.get("/api/v1/wallets/sync/").data["results"][0]
        self.assertTrue(pulled["archived"])
