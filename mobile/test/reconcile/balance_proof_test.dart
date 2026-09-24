import 'dart:convert';

import 'package:economy/core/reconcile/balance_proof.dart';
import 'package:economy/core/sms/jalali.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

/// سناریوی واقعیِ گزارشِ کاربرِ دوم (شماره‌ها ساختگی، مبلغ و مانده‌ها عینِ گزارش):
/// پیامک‌های «بانکداری دیجیتال پاسارگاد» (واریزِ وام، قسط، کارمزد) شماره‌ی حساب ندارند و رد
/// می‌شدند، پس زنجیره‌ی مانده‌ی حسابِ پاسارگاد ۹۲ میلیون ریال اختلاف داشت.
const _acct = '777.888.10000001.1';
const _pasargad = 'B.Pasargad';
const _digital = '+985000114';

/// زمانِ تهران (ساعتِ دیواری) به UTC.
DateTime _tehran(int jy, int jm, int jd, int h, int m) {
  final g = jalaliToGregorian(jy, jm, jd);
  return DateTime.utc(g[0], g[1], g[2], h, m).subtract(kIranOffset);
}

String _two(int n) => n.toString().padLeft(2, '0');

RawSms _pas(int jm, int jd, int h, int m, String signedAmount, String balance) => RawSms(
      sender: _pasargad,
      body: '$_acct\n$signedAmount\n${_two(jm)}/${_two(jd)}_${_two(h)}:${_two(m)}\nمانده: $balance',
      receivedAt: _tehran(1405, jm, jd, h, m),
    );

RawSms _fee(int jm, int jd, int h, int m, String amount, String balance) => RawSms(
      sender: _pasargad,
      body: 'کارمزد ارائه خدمات با شناسه 7000000001 به مبلغ $amount ریال جهت عضویت در حساب '
          'پشتوانه با موفقیت پرداخت گردید.\nموجودی حساب دیجیتال: $balance ریال\n'
          'زمان: 1405/${_two(jm)}/${_two(jd)} ${_two(h)}:${_two(m)}:28',
      receivedAt: _tehran(1405, jm, jd, h, m),
    );

RawSms _loan(int jm, int jd, int h, int m, String amount, String balance) => RawSms(
      sender: _digital,
      body: '*بانکداري ديجيتالي پاسارگاد*\nکاربر گرامی؛\nمبلغ $amount ریال از طریق حساب پشتوانه '
          'برای شما واریز شد.\nموجودی حساب دیجیتال پاد: $balance\nتاریخ: 1405/${_two(jm)}/${_two(jd)}',
      receivedAt: _tehran(1405, jm, jd, h, m),
    );

RawSms _installment(int jm, int jd, int h, int m, String amount) => RawSms(
      sender: _digital,
      body: '*بانکداري ديجيتالي پاسارگاد*\nاقساط قرارداد 1001 - حساب پشتوانه به مبلغ $amount ریال '
          'از حساب دیجیتال با موفقیت پرداخت گردید.\nتعداد اقساط باقی مانده:0\nتعداد اقساط معوق: 0',
      receivedAt: _tehran(1405, jm, jd, h, m),
    );

/// ۶ تا ۸ شهریور و ۲۲ تا ۲۴ مرداد، همان‌طور که در صندوقِ گوشی بود.
final _account = [
  _pas(5, 21, 19, 29, '-940,000', '145,227,893'),
  _installment(5, 22, 10, 26, '40,781,370'),
  _pas(5, 22, 10, 28, '-1,200,000', '103,246,523'),
  _pas(5, 22, 10, 29, '-870,000', '102,376,523'),
  _pas(5, 22, 10, 34, '-140,000', '102,236,523'),
  // واریزِ وام زودتر از کارمزد رسیده ولی مانده‌اش بعد از کارمزد است.
  _loan(5, 22, 10, 34, '70,000,000', '171,336,523'),
  _fee(5, 22, 10, 35, '900,000', '101,336,523'),
  _pas(5, 24, 17, 34, '-2,930,000', '168,406,523'),
  _pas(6, 6, 22, 5, '-2,928,000', '284,641,629'),
  _installment(6, 7, 0, 47, '71,367,398'),
  _pas(6, 7, 0, 50, '-870,000', '212,404,231'),
  _pas(6, 7, 16, 36, '-730,000', '211,674,231'),
  _pas(6, 7, 17, 5, '-1,300,000', '210,374,231'),
  _pas(6, 7, 17, 10, '-800,000', '209,574,231'),
  _pas(6, 7, 21, 11, '-200,000', '209,374,231'),
  _fee(6, 7, 21, 11, '1,200,000', '208,174,231'),
  _loan(6, 7, 21, 11, '100,000,000', '308,174,231'),
  _pas(6, 8, 11, 26, '-6,260,000', '301,914,231'),
];

final _feeJune = _account.firstWhere((s) => s.body.contains('1,200,000 ریال جهت'));

void main() {
  final now = _tehran(1405, 7, 2, 23, 0);
  late FakeTransactionStore store;

  setUp(() async {
    store = FakeTransactionStore(clock: () => now);
    await store.addAllowedSender(_pasargad, bankId: 'pasargad');
    await store.addAllowedSender(_digital);
  });

  Future<List<TransactionRecord>> pasargad() async =>
      [for (final t in await store.getAll()) if (t.accountRef == _acct) t];

  test('وام، قسط و کارمزدِ بی‌شماره با مانده به حسابِ پاسارگاد وصل می‌شوند', () async {
    final r = await SmsImporter(store).importAll(_account.reversed.toList());
    expect(r.proven, 6);
    expect(r.created, _account.length);
    final list = await pasargad();
    expect(list, hasLength(_account.length));
    // هر خوشه از اول تا آخرش: جمعِ حرکت‌ها = تغییرِ مانده‌ی بانک.
    int net(DateTime from, DateTime to) => list
        .where((t) => t.effectiveTime.isAfter(from) && !t.effectiveTime.isAfter(to))
        .fold(0, (s, t) => s + t.signedAmount);
    expect(net(_tehran(1405, 5, 21, 19, 29), _tehran(1405, 5, 24, 17, 34)), 168406523 - 145227893);
    expect(net(_tehran(1405, 6, 6, 22, 5), _tehran(1405, 6, 8, 11, 26)), 301914231 - 284641629);
    // واریزِ وامِ فقط‌تاریخ‌دار زمانِ رسیدن را گرفته، نه «اولِ روز».
    expect(list.where((t) => t.amountRial == 100000000).single.effectiveTime,
        _tehran(1405, 6, 7, 21, 11));
    final installments = list.where((t) => t.amountRial == 71367398).single;
    expect(installments.balanceAfterRial, isNull); // «باقی مانده:0» مانده نیست
    expect(installments.kind, 'expense');
  });

  test('بی‌شماره‌ای که مانده ثابتش نکند ثبت نمی‌شود (قانون سر جایش است)', () async {
    await SmsImporter(store).importAll(_account);
    final stray = [
      // قسطی با مبلغی که هیچ ناجوری‌ای را توضیح نمی‌دهد.
      _installment(6, 20, 9, 0, '12,345,678'),
      // واریزِ وامی که مانده‌اش با هیچ حسابی جور نیست.
      _loan(6, 21, 9, 0, '5,000,000', '999,999,999'),
      // همان کارمزدِ ثبت‌شده، دوباره (بانک دو بار فرستاده).
      RawSms(
          sender: _pasargad,
          body: _feeJune.body,
          receivedAt: _feeJune.receivedAt!.add(const Duration(minutes: 40))),
      // دیجی‌پی: بانک ندارد.
      RawSms(
          sender: _digital,
          body: 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nمبلغ 100,000,000 ریال واریز شد.',
          receivedAt: _tehran(1405, 6, 7, 0, 48)),
    ];
    final r = await SmsImporter(store).importAll(stray);
    expect(r.created, 0);
    expect(r.proven, 0);
  });

  test('پیامکِ زنده: کارمزدِ بی‌شماره همان لحظه به حساب وصل می‌شود', () async {
    await SmsImporter(store).importAll(_account.take(5).toList());
    final fee = _fee(5, 22, 10, 36, '100,000', '102,136,523');
    final imported = await SmsImporter(store).importOne(fee);
    expect(imported, isNotNull);
    expect((await store.getById(imported!.id))!.accountRef, _acct);
  });

  test('دو حساب که هر دو جور شوند → مبهم، ثبت نمی‌شود', () {
    TransactionRecord rec(String id, String acct, int bal) => TransactionRecord(
          id: id,
          bankId: 'pasargad',
          accountRef: acct,
          kind: 'expense',
          amountRial: 1000,
          balanceAfterRial: bal,
          transactionDate: DateTime.utc(2026, 8, 1, 10),
          smsBody: 'x',
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        );
    final proven = proveByBalance(
      live: [rec('a', '1.1.10000001.1', 50000), rec('b', '1.1.10000002.1', 50000)],
      candidates: [
        ProofCandidate(
            key: 'c',
            bankId: 'pasargad',
            signedAmount: -500,
            balanceAfterRial: 49500,
            at: DateTime.utc(2026, 8, 1, 10, 5)),
      ],
    );
    expect(proven, isEmpty);
  });

  test('proofTime: متنِ فقط‌تاریخ → زمانِ رسیدنِ همان روز', () {
    final dateOnly = _tehran(1405, 6, 7, 0, 0);
    final received = _tehran(1405, 6, 7, 21, 11);
    expect(proofTime(dateOnly, received), received);
    expect(proofTime(_tehran(1405, 6, 7, 21, 0), received), _tehran(1405, 6, 7, 21, 0));
    expect(proofTime(dateOnly, _tehran(1405, 6, 9, 8, 0)), dateOnly);
  });

  group('تعمیر (نسخه‌ی قبل حذفشان کرده بود)', () {
    late DashboardController c;

    setUp(() async {
      c = DashboardController(store, clock: () => now)..readInbox = () async => _account;
    });

    /// ثبتِ پیامک و حذفش، مثلِ پارسر/قانونِ نسخه‌ی قبل.
    Future<String> storedThenDeleted(RawSms sms, {String? bankId}) async {
      final out = await store.saveParsed(
          const SmsParser().parse(sender: sms.sender, body: sms.body, bankId: bankId),
          sender: sms.sender,
          receivedAt: sms.receivedAt);
      await store.deleteTransaction(out.id);
      return out.id;
    }

    test('حذف‌شده‌هایی که مانده ثابتشان می‌کند برمی‌گردند؛ تکراری و حذفِ دستیِ تازه نه', () async {
      // تراکنش‌های شماره‌دار ثبت شده‌اند.
      await SmsImporter(store).importAll([for (final s in _account) if (s.sender == _pasargad && !s.body.startsWith('کارمزد')) s]);
      // وام/قسط/کارمزدها پیش از قانون ثبت و بعد با قانون حذف شده بودند.
      final old = <String>[
        for (final s in _account)
          if (s.sender == _digital || s.body.startsWith('کارمزد'))
            await storedThenDeleted(s, bankId: s.sender == _pasargad ? 'pasargad' : null),
      ];
      // پارسرِ قبلی «تعداد اقساط باقی مانده:0» را مانده‌ی صفر خوانده بود.
      await store.applyPatches([
        for (final id in old)
          if ((await store.getById(id))!.amountRial! > 40000000 &&
              (await store.getById(id))!.kind == 'expense')
            TxPatch(id, set: {'balance_after_rial': 0}),
      ]);
      // پیامکی که بانک دوباره فرستاده (همان متن) و حذف شده: تکراری است، برنمی‌گردد.
      final dupSms = RawSms(
          sender: _pasargad,
          body: _account[4].body,
          receivedAt: _account[4].receivedAt!.add(const Duration(minutes: 25)));
      final dup = await storedThenDeleted(dupSms, bankId: 'pasargad');
      // کاربر بعد از این نسخه یکی را دستی حذف می‌کند → برنمی‌گردد.
      await c.load();
      final removedByUser =
          (await pasargad()).firstWhere((t) => t.balanceAfterRial == 102376523).id;
      await c.deleteTransaction(removedByUser);
      expect(jsonDecode(store.settings[SettingKeys.userDeleted]!), [removedByUser]);

      final r = await c.runRepair();
      expect(r.proven, old.length);
      for (final id in old) {
        final t = (await store.getById(id))!;
        expect(t.isDeleted, isFalse, reason: t.smsBody);
        expect(t.accountRef, _acct);
      }
      expect((await store.getById(dup))!.isDeleted, isTrue);
      expect((await store.getById(removedByUser))!.isDeleted, isTrue);
      // قسطِ قدیمی «باقی مانده:0» را مانده‌ی صفر خوانده بود؛ درست شد.
      expect(
          (await pasargad()).where((t) => t.amountRial == 40781370).single.balanceAfterRial, isNull);
      expect(c.itemsIn(const Period.all()).where((t) => t.amountRial == 100000000), hasLength(1));
    });
  });
}
