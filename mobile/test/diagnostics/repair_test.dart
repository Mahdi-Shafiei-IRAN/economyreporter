import 'package:economy/core/diagnostics/balance_chain.dart';
import 'package:economy/core/diagnostics/repair.dart';
import 'package:economy/core/sms/jalali.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

// الگوی واقعیِ گزارشِ کاربر (شماره حساب ساختگی).
const _mellat = 'Bank Mellat';
const _acct = '1000005596';
String _mellatBody(String kind, String amount, String balance, String when) =>
    'حساب$_acct\n$kind$amount\nمانده$balance\n$when';
const _digipay = '+989900004602';
const _digipayBody = 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: 72٬750٬000 ریال';
const _refundBody = ' بازگشت پول\nمبلغ 31,000 ریال به دیجی‌کارت شما واریز شد.\nدیجی‌پـی';

final _now = DateTime.utc(2026, 9, 24, 10);
const _allowed = [
  AllowedSender(id: 's1', address: _mellat, bankId: 'mellat'),
  AllowedSender(id: 's2', address: _digipay),
];

RawSms _sms(String sender, String body, DateTime at) =>
    RawSms(sender: sender, body: body, receivedAt: at);

/// ثبتِ یک پیامک همان‌طور که importer/saveParsed می‌کرد (حتی بی‌قانون).
TransactionRecord _stored(String id, RawSms sms,
    {String origin = 'local', bool withBody = true}) {
  final bankId = sms.sender == _mellat ? 'mellat' : null;
  final p = const SmsParser().parse(sender: sms.sender, body: sms.body, bankId: bankId);
  final r = TransactionRecord.fromParsed(
    p,
    id: id,
    now: sms.receivedAt!,
    sourceMessageHash:
        smsFingerprint(sender: sms.sender, body: sms.body, receivedAt: sms.receivedAt),
    smsReceivedAt: sms.receivedAt,
    smsContentHash: smsContentHash(sender: sms.sender, body: sms.body),
  );
  if (withBody) return recordWith(r, {'origin': origin});
  // نسخه‌ای که از سرور برگشته: بی‌متن و بی‌شماره‌ی حساب (به سرور نمی‌رود).
  return recordWith(r, {
    'origin': 'remote',
    'sms_body': null,
    'sms_sender': null,
    'sms_content_hash': null,
    'account_ref': null,
  });
}

void main() {
  group('planRepair', () {
    test('نسخه‌ی سرور (بی‌متن و بی‌شماره) به پیامکش وصل می‌شود و شماره‌ی حساب می‌گیرد', () {
      final sms = _sms(_mellat, _mellatBody('برداشت', '700,000', '54,343,831', '05/05/24-15:35'),
          DateTime.utc(2026, 8, 15, 12, 5));
      final remote = _stored('r1', sms, withBody: false);
      expect(remote.accountRef, isNull);

      final plan = planRepair(records: [remote], inbox: [sms], allowed: _allowed, now: _now);
      expect(plan.result.adopted, 1);
      expect(plan.result.removed, 0);
      final set = plan.patches.single.set;
      expect(set['origin'], 'local');
      expect(set['sms_body'], sms.body);
      expect(set['account_ref'], _acct);
      expect(plan.patches.single.delete, isFalse);
    });

    test('پیامکِ بی‌شماره (اعتبار دیجی‌پی، بازگشت پول) کنار می‌رود؛ شماره‌دار می‌ماند', () {
      final records = [
        _stored('d1', _sms(_digipay, _digipayBody, DateTime.utc(2026, 9, 16, 10))),
        _stored('d2', _sms(_digipay, _refundBody, DateTime.utc(2026, 8, 20, 16))),
        _stored('m1', _sms(_mellat, _mellatBody('برداشت', '100,000', '1,000,000', '05/06/25-10:00'),
            DateTime.utc(2026, 9, 16, 6, 30))),
      ];
      final plan = planRepair(records: records, inbox: const [], allowed: _allowed, now: _now);
      expect(plan.result.removedIds, unorderedEquals(['d1', 'd2']));
      expect([for (final p in plan.patches) if (p.delete) p.id], unorderedEquals(['d1', 'd2']));
    });

    test('تراکنشِ دستی‌چسبانده یا برگردانده‌شده حذف نمی‌شود', () {
      final pinned = recordWith(
          _stored('d1', _sms(_digipay, _digipayBody, DateTime.utc(2026, 9, 16, 10))),
          {'pinned_wallet_id': 'w1'});
      final kept = _stored('d2', _sms(_digipay, _refundBody, DateTime.utc(2026, 8, 20, 16)));
      final plan = planRepair(
          records: [pinned, kept], inbox: const [], allowed: _allowed, now: _now, kept: {'d2'});
      expect(plan.result.removed, 0);
    });

    test('شماره‌ی حساب/مانده‌ای که ثبتِ قدیمی نداشت از متن تکمیل می‌شود', () {
      final sms = _sms(_mellat, _mellatBody('برداشت', '100,000', '1,000,000', '05/06/25-10:00'),
          DateTime.utc(2026, 9, 16, 6, 30));
      final old = recordWith(_stored('m1', sms), {'account_ref': null, 'balance_after_rial': null});
      final plan = planRepair(records: [old], inbox: const [], allowed: _allowed, now: _now);
      expect(plan.result.backfilled, 1);
      expect(plan.patches.single.set,
          containsPair('account_ref', _acct));
      expect(plan.patches.single.set, containsPair('balance_after_rial', 1000000));
    });

    test('«24:00»ِ تجارت: تاریخ به پایانِ همان روز اصلاح می‌شود', () {
      const body = '*بانک تجارت*\nحساب: 1000004816\nواریز: 60 ریال\nاز طريق: شعبه ديجيتال\n'
          'مانده: 705,160 ریال\n1405/05/31\n24:00';
      final sms = _sms('TejaratBank', body, DateTime.utc(2026, 8, 23, 4, 11));
      // ثبتِ قدیمی: ساعت دور ریخته شده بود = ۰۰:۰۰ همان روز
      final old = recordWith(_stored('t1', sms), {
        'transaction_date': DateTime.utc(2026, 8, 21, 20, 30).toIso8601String(),
      });
      final plan = planRepair(
          records: [old],
          inbox: const [],
          allowed: const [AllowedSender(id: 't', address: 'TejaratBank', bankId: 'tejarat')],
          now: _now);
      final fixed = DateTime.parse(plan.patches.single.set['transaction_date'] as String);
      expect(fixed, DateTime.utc(2026, 8, 22, 20, 30)); // ۰۰:۰۰ ۱ شهریور به وقت ایران
    });
  });

  test('extractOccurredAt: «24:00» = ۰۰:۰۰ روزِ بعد', () {
    final at = extractOccurredAt('1405/05/31 24:00')!;
    final next = extractOccurredAt('1405/06/01 00:00')!;
    expect(at, next);
  });

  group('ترتیبِ پیامک‌های هم‌دقیقه (گزارشِ واقعی، ۲۵ شهریور)', () {
    TransactionRecord tx(String id, int amount, int balance, int minute, {int recv = 0}) {
      final at = DateTime.utc(2026, 9, 16, 8, minute); // ۱۱:۴۰/۱۱:۴۷ تهران
      return TransactionRecord(
        id: id,
        bankId: 'mellat',
        accountRef: _acct,
        kind: 'expense',
        amountRial: amount,
        balanceAfterRial: balance,
        transactionDate: at,
        smsReceivedAt: at.add(Duration(seconds: recv)),
        createdAt: at,
        updatedAt: at,
      );
    }

    final before = tx('p', 660000, 150557110, 0);
    // ترتیبِ رسیدن: ۱۴۳هزار، ۲٫۵م، ۳۶۰هزار — ولی ترتیبِ واقعی ۱۴۳هزار، ۳۶۰هزار، ۲٫۵م.
    final a = tx('a', 143000, 150414110, 10, recv: 1);
    final b = tx('b', 2500000, 147554110, 10, recv: 2);
    final c = tx('c', 360000, 150054110, 10, recv: 3);
    final deleted = tx('del', 2500000, 145054110, 17)
        .copyWith(deletedAt: DateTime.utc(2026, 9, 20));
    final d = tx('d', 1500000, 143554110, 17, recv: 5);

    test('sortForBalance ترتیبی را انتخاب می‌کند که مانده‌ها جور شوند', () {
      final list = [d, b, c, a, before];
      sortForBalance(list);
      expect(list.map((t) => t.id), ['p', 'a', 'c', 'b', 'd']);
      expect(realBalanceRial([before, a, b, c]), 147554110);
    });

    test('زنجیره: دیگر «ترتیب جابه‌جا» نیست و برداشتِ حذف‌شده برای برگرداندن پیشنهاد می‌شود',
        () {
      final r = auditBalanceChains([before, a, b, c, d], deleted: [deleted]);
      final links = r.accounts.single.links;
      expect(links.map((l) => l.status), [
        ChainStatus.start,
        ChainStatus.ok,
        ChainStatus.ok,
        ChainStatus.ok,
        ChainStatus.mismatch,
      ]);
      expect(links.last.diffRial, -2500000);
      expect(links.last.restoreCandidate?.id, 'del');
    });
  });

  group('DashboardController', () {
    late FakeTransactionStore store;
    late DashboardController c;
    late List<RawSms> inbox;

    setUp(() async {
      store = FakeTransactionStore(clock: () => _now);
      await store.addAllowedSender(_mellat, bankId: 'mellat');
      await store.addAllowedSender(_digipay);
      final old1 = _sms(_mellat, _mellatBody('برداشت', '100,000', '100,282,079', '05/07/01-05:40'),
          DateTime.utc(2026, 9, 23, 2, 10));
      final old2 = _sms(_mellat, _mellatBody('برداشت', '63,881,900', '36,400,179', '05/07/01-13:05'),
          DateTime.utc(2026, 9, 23, 9, 35));
      final now1 = _sms(_mellat, _mellatBody('برداشت', '15,840,620', '20,559,559', '05/07/01-15:40'),
          DateTime.utc(2026, 9, 23, 12, 10));
      final junk = _sms(_digipay, _digipayBody, DateTime.utc(2026, 9, 16, 10));
      inbox = [old1, old2, now1, junk];
      // نصبِ قبلی: دو پیامکِ قدیمی فقط به‌صورتِ نسخه‌ی سرور (بی‌شماره) مانده‌اند.
      store.addRecord(_stored('r1', old1, withBody: false));
      store.addRecord(_stored('r2', old2, withBody: false));
      // پیامکِ تازه محلی ثبت شده؛ اعتبارِ دیجی‌پی هم پیش از قانون ثبت شده بود.
      store.addRecord(_stored('m1', now1));
      store.addRecord(_stored('j1', junk));
      c = DashboardController(store, clock: () => _now)..readInbox = () async => inbox;
      await c.load();
    });

    test('پیش از تعمیر: یک حساب دو بار شمرده می‌شود', () {
      expect(c.balanceChains().splitHints, isNotEmpty);
      // حساب (۲۰٫۵م) + همان حساب از نسخه‌ی سرور (۳۶٫۴م) + «اعتبار» دیجی‌پی (−۷۲٫۷م)
      expect(realBalanceRial(c.itemsIn(const Period.all())), 20559559 + 36400179 - 72750000);
    });

    test('runRepair: وصل به پیامک، حذفِ بی‌شماره، موجودیِ درست؛ یک بار و قابل تکرار', () async {
      final result = await c.runRepair();
      expect(result.adopted, 2);
      expect(result.removedIds, ['j1']);
      expect(c.lastRepair?.adopted, 2);

      // حالا همه یک حساب‌اند: موجودی = مانده‌ی آخرین پیامک.
      expect(c.balanceChains().splitHints, isEmpty);
      expect(c.balanceChains().accounts.single.links, hasLength(3));
      expect(realBalanceRial(c.itemsIn(const Period.all())), 20559559);

      // اجرای دوباره چیزی را خراب نمی‌کند.
      final again = await c.runRepair();
      expect(again.changedAnything, isFalse);
      expect(await c.runRepairOnce(), isNull); // «یک بار» قبلاً انجام شده
    });

    test('برگرداندن: تراکنشِ حذف‌شده برمی‌گردد و تعمیرِ بعدی دوباره حذفش نمی‌کند', () async {
      await c.runRepair();
      final junk = c.deletedSms.singleWhere((t) => t.id == 'j1');
      await c.restoreTransaction(junk);
      expect(c.cachedById('j1'), isNotNull);
      await c.runRepair();
      expect(c.cachedById('j1'), isNotNull);
    });

    test('fixKind: نوعِ برعکس اصلاح می‌شود و از بازبینی بیرون می‌آید', () async {
      await c.fixKind(c.cachedById('m1')!, 'income');
      expect(c.cachedById('m1')!.kind, 'income');
      expect(c.cachedById('m1')!.needsReview, isFalse);
    });

    test('mergeAccounts: گروهِ بی‌شماره به حسابِ شماره‌دار می‌پیوندد', () async {
      final hint = c.balanceChains().splitHints.single;
      expect(hint.keep.hasId, isTrue);
      await c.mergeAccounts(hint);
      expect(c.balanceChains().splitHints, isEmpty);
      expect(c.cachedById('r1')!.accountRef, _acct);
    });
  });
}
