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
}
