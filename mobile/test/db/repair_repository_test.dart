import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

/// تعمیر/برگرداندن/یکی کردن روی پایگاه‌داده‌ی واقعی (همان مسیرِ گوشی).
void main() {
  late Database db;
  late TransactionRepository repo;
  final now = DateTime.utc(2026, 9, 24, 10);

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db, clock: () => now);
    await repo.addAllowedSender('Bank Mellat', bankId: 'mellat');
    await repo.addAllowedSender('+989900004602');
  });

  tearDown(() async => db.close());

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  test('applyPatches: حذف و برگرداندن، هر دو برای سرور صف می‌شوند', () async {
    final out = await repo.saveParsed(
        const SmsParser().parse(sender: 'Bank Mellat', body: 'حساب1000005596\nبرداشت100,000\nمانده1,000,000'),
        sender: 'Bank Mellat',
        receivedAt: now);
    await db.delete('outbox');

    await repo.applyPatches([TxPatch(out.id, delete: true)]);
    expect((await repo.getById(out.id))!.isDeleted, isTrue);
    expect((await repo.getById(out.id))!.toSyncPayload()['is_deleted'], isTrue);
    expect(await outboxCount(), 1);
    expect((await repo.deletedSmsTransactions()).single.id, out.id);

    await db.delete('outbox');
    await repo.applyPatches([TxPatch(out.id, restore: true)]);
    expect((await repo.getById(out.id))!.isDeleted, isFalse);
    expect((await repo.getById(out.id))!.toSyncPayload()['is_deleted'], isFalse);
    expect(await outboxCount(), 1);
  });

  test('نگاشتِ «یکی کن»: پیامک‌های بعدیِ آن کارت به همان حساب می‌روند', () async {
    await repo.setSetting(
        SettingKeys.accountAliases,
        AccountIdentity.encodeMap({
          'mellat|c:1234':
              const AccountIdentity(bankId: 'mellat', accountRef: '1000005596'),
        }));
    final out = await repo.saveParsed(
        const SmsParser().parse(
            sender: 'Bank Mellat', body: 'بانک ملت\nخرید از کارت 1234\nمبلغ: 750,000 ریال'),
        sender: 'Bank Mellat',
        receivedAt: now);
    final t = (await repo.getById(out.id))!;
    expect(t.accountRef, '1000005596');
    expect(t.cardLast4, isNull);
  });

  test('runRepair روی دیتابیس: نسخه‌ی سرور وصل، دیجی‌پی کنار، موجودی یکی', () async {
    const mellat = 'Bank Mellat';
    final old = RawSms(
        sender: mellat,
        body: 'حساب1000005596\nبرداشت63,881,900\nمانده36,400,179\n05/07/01-13:05',
        receivedAt: DateTime.utc(2026, 9, 23, 9, 35));
    final fresh = RawSms(
        sender: mellat,
        body: 'حساب1000005596\nبرداشت15,840,620\nمانده20,559,559\n05/07/01-15:40',
        receivedAt: DateTime.utc(2026, 9, 23, 12, 10));
    final junk = RawSms(
        sender: '+989900004602',
        body: 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: 72٬750٬000 ریال',
        receivedAt: DateTime.utc(2026, 9, 16, 10));

    // نسخه‌ی سرور (از نصبِ قبلی): بی‌متن و بی‌شماره‌ی حساب.
    await repo.applyRemote({
      'id': 'remote-old',
      'kind': 'expense',
      'amount_rial': 63881900,
      'balance_after_rial': 36400179,
      'bank_id': 'mellat',
      'source': 'sms',
      'source_message_hash':
          smsFingerprint(sender: old.sender, body: old.body, receivedAt: old.receivedAt),
      'transaction_date': '2026-09-23T09:35:00Z',
      'updated_at': '2026-09-23T09:36:00Z',
    });
    await SmsImporter(repo).importAll([fresh]);
    // پیش از قانون، اعتبارِ دیجی‌پی هزینه ثبت شده بود.
    await repo.saveParsed(const SmsParser().parse(sender: junk.sender, body: junk.body),
        sender: junk.sender, receivedAt: junk.receivedAt);

    final c = DashboardController(repo, clock: () => now)
      ..readInbox = () async => [old, fresh, junk];
    await c.load();
    expect(c.balanceChains().splitHints, isNotEmpty);

    final r = await c.runRepair();
    expect(r.adopted, 1);
    expect(r.removed, 1);
    expect(r.imported, 0); // هیچ‌چیز دوباره (تکراری) وارد نشد

    final adopted = (await repo.getById('remote-old'))!;
    expect(adopted.origin, 'local');
    expect(adopted.accountRef, '1000005596');
    expect(adopted.smsBody, old.body);
    expect(c.balanceChains().splitHints, isEmpty);
    expect(realBalanceRial(c.itemsIn(const Period.all())), 20559559);

    // یک بار: بار دوم اجرا نمی‌شود.
    expect(await c.runRepairOnce(), isNull);
  });

  test('برداشتن و مجاز کردنِ دوباره‌ی فرستنده روی پایگاه‌داده‌ی واقعی: تراکنش‌ها برمی‌گردند',
      () async {
    final inbox = [
      RawSms(
          sender: 'Bank Mellat',
          body: 'واریز سود کوتاه مدت\nحساب4900000002\nمبلغ4,033\n05/07/01',
          receivedAt: now.subtract(const Duration(days: 1))),
      RawSms(
          sender: 'Bank Mellat',
          body: 'حساب4900000002\nواریز485\nمانده1,040,193\n05/06/15-10:39',
          receivedAt: now.subtract(const Duration(days: 18))),
    ];
    await SmsImporter(repo).importAll(inbox);
    final c = DashboardController(repo, clock: () => now)..readInbox = () async => inbox;
    await c.load();
    final mellat = c.allowedSenders.firstWhere((s) => s.address == 'Bank Mellat');

    await c.removeAllowedSender(mellat.id, deleteTransactions: true);
    expect(c.transactionsOfSender('Bank Mellat'), isEmpty);
    expect(await repo.deletedSmsTransactions(), hasLength(2));

    await c.addAllowedSender('Bank Mellat', bankId: 'mellat');
    expect(c.transactionsOfSender('Bank Mellat'), hasLength(2));
    expect(await repo.deletedSmsTransactions(), isEmpty);
    expect((await SmsImporter(repo).importAll(inbox)).created, 0);
  });

  test('نصبِ دوباره روی پایگاه‌داده‌ی واقعی: نسخه‌ی سرور با پیامکش شماره و متن می‌گیرد', () async {
    final sms = RawSms(
        sender: 'Bank Mellat',
        body: 'حساب4900000002\nواریز485\nمانده1,040,193\n05/06/15-10:39',
        receivedAt: now.subtract(const Duration(days: 18)));
    final interest = RawSms(
        sender: 'Bank Mellat',
        body: 'واریز سود کوتاه مدت\nحساب4900000002\nمبلغ4,033\n05/07/01',
        receivedAt: now.subtract(const Duration(days: 1)));
    String hash(RawSms s) =>
        smsFingerprint(sender: s.sender, body: s.body, receivedAt: s.receivedAt);
    // همان چیزی که بعد از ورود از سرور می‌آید: بدونِ متن و شماره‌ی حساب؛ یکی حذف‌شده.
    await repo.applyRemote({
      'id': 'srv-1',
      'kind': 'income',
      'amount_rial': 485,
      'balance_after_rial': 1040193,
      'bank_id': 'mellat',
      'transaction_date': sms.receivedAt!.toIso8601String(),
      'source_message_hash': hash(sms),
      'is_deleted': false,
    });
    await repo.applyRemote({
      'id': 'srv-2',
      'kind': 'income',
      'amount_rial': 4033,
      'bank_id': 'mellat',
      'transaction_date': interest.receivedAt!.toIso8601String(),
      'source_message_hash': hash(interest),
      'is_deleted': true,
    });

    expect((await SmsImporter(repo).importAll([sms, interest])).created, 0);
    final live = (await repo.getById('srv-1'))!;
    expect(live.accountRef, '4900000002');
    expect(live.origin, 'local');
    expect(live.smsBody, sms.body);
    final deleted = (await repo.getById('srv-2'))!;
    expect(deleted.isDeleted, isTrue);
    expect(deleted.smsBody, interest.body); // حالا در عیب‌یابی دیده و برگردانده می‌شود
  });

  test('کارمزدِ بی‌شماره‌ی پاسارگاد روی پایگاه‌داده‌ی واقعی با مانده به حساب وصل می‌شود', () async {
    await repo.addAllowedSender('B.Pasargad', bankId: 'pasargad');
    final t0 = now.subtract(const Duration(days: 3));
    final r = await SmsImporter(repo).importAll([
      RawSms(
          sender: 'B.Pasargad',
          body: '777.888.10000001.1\n-200,000\n06/07_21:11\nمانده: 209,374,231',
          receivedAt: t0),
      RawSms(
          sender: 'B.Pasargad',
          body: 'کارمزد ارائه خدمات با شناسه 7000000001 به مبلغ 1,200,000 ریال جهت عضویت در حساب '
              'پشتوانه با موفقیت پرداخت گردید.\nموجودی حساب دیجیتال: 208,174,231 ریال',
          receivedAt: t0.add(const Duration(minutes: 1))),
    ]);
    expect(r.created, 2);
    expect(r.proven, 1);
    final fee = (await repo.getAll()).firstWhere((t) => t.amountRial == 1200000);
    expect(fee.accountRef, '777.888.10000001.1');
    expect(fee.balanceAfterRial, 208174231);
  });
}
