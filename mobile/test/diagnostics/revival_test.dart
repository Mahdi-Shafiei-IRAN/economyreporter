import 'dart:convert';

import 'package:economy/core/diagnostics/repair.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

/// مشکلِ واقعی (کاربرِ دوم): پیامکی که یک بار (پارسرِ قدیمی، تعمیرِ خودکار، یا «بردار و
/// تراکنش‌هایش را حذف کن») حذف شده بود، دیگر هیچ‌وقت ثبت نمی‌شد، چون ضدتکرار حذف‌شده‌ها
/// را هم می‌بیند؛ نه خواندنِ دوباره‌ی صندوق کمک می‌کرد نه مجاز کردنِ دوباره‌ی فرستنده.
void main() {
  final now = DateTime.utc(2026, 9, 24, 12);
  const mellat = 'Bank Mellat';
  final interest = RawSms(
      sender: mellat,
      body: 'واریز سود علی الحساب\nسپرده4900000001\nبه حساب4900000002\nمبلغ86,184\n05/07/01',
      receivedAt: DateTime.utc(2026, 9, 23, 2, 39));
  final shortTerm = RawSms(
      sender: mellat,
      body: 'واریز سود کوتاه مدت\nحساب4900000002\nمبلغ4,033\n05/07/01',
      receivedAt: DateTime.utc(2026, 9, 23, 2, 39));
  final deposit = RawSms(
      sender: mellat,
      body: 'حساب4900000002\nواریز485\nمانده1,040,193\n05/06/15-10:39',
      receivedAt: DateTime.utc(2026, 9, 6, 7, 9));
  final inbox = [interest, shortTerm, deposit];

  late FakeTransactionStore store;
  late DashboardController c;

  Future<String> save(RawSms sms) async => (await store.saveParsed(
          const SmsParser().parse(sender: sms.sender, body: sms.body, bankId: 'mellat'),
          sender: sms.sender,
          receivedAt: sms.receivedAt))
      .id;

  Future<bool> alive(String id) async => !(await store.getById(id))!.isDeleted;

  setUp(() async {
    store = FakeTransactionStore(clock: () => now);
    await store.addAllowedSender(mellat, bankId: 'mellat');
    c = DashboardController(store, clock: () => now)..readInbox = (() async => inbox);
  });

  test('حذف‌شده‌ی تعمیرِ نسخه‌ی قبل برمی‌گردد؛ حذفِ دستیِ کاربر نه', () async {
    final byRepair = await save(interest);
    final byUser = await save(shortTerm);
    // تعمیرِ نسخه‌ی قبل (پارسرِ قدیمی شماره‌ی حساب را نمی‌خواند) این را کنار گذاشته بود…
    await store.applyPatches([TxPatch(byRepair, delete: true)]);
    await store.setSetting(
        SettingKeys.repairResult,
        jsonEncode({
          'at': now.subtract(const Duration(days: 3)).toIso8601String(),
          'removed': [byRepair],
        }));
    // …و این را خودِ کاربر حذف کرده.
    await c.load();
    await c.deleteTransaction(byUser);

    // خواندنِ دوباره‌ی صندوق هیچ‌کدام را برنمی‌گرداند (ضدتکرار)؛ مشکلِ اصلی همین بود.
    expect((await SmsImporter(store).importAll(inbox)).created, 1); // فقط deposit

    final r = await c.runRepairOnce();
    expect(r, isNotNull);
    expect(r!.revived, 1);
    expect(r.parserVersion, kParserVersion);
    expect(await alive(byRepair), isTrue);
    expect(await alive(byUser), isFalse);
    expect((await store.getById(byRepair))!.accountRef, '4900000002');
    expect(c.lastRepair!.revived, 1);

    // تا پارسر عوض نشود دوباره اجرا نمی‌شود.
    expect(await c.runRepairOnce(), isNull);
  });

  test('نتیجه‌ی تعمیرِ بدونِ نسخه‌ی پارسر (نسخه‌های قبل) → یک بار دوباره اجرا می‌شود', () async {
    await store.setSetting(SettingKeys.repairResult,
        jsonEncode({'at': now.toIso8601String(), 'removed': <String>[]}));
    expect(await c.runRepairOnce(), isNotNull);
    expect(await c.runRepairOnce(), isNull);
  });

  test('برداشتنِ فرستنده «با تراکنش‌هایش» و مجاز کردنِ دوباره → تراکنش‌ها برمی‌گردند', () async {
    await SmsImporter(store).importAll(inbox);
    await c.load();
    expect(c.transactionsOfSender(mellat), hasLength(3));

    await c.removeAllowedSender(c.allowedSenders.single.id, deleteTransactions: true);
    expect((await store.getAll()), isEmpty);

    await c.addAllowedSender(mellat, bankId: 'mellat');
    expect(c.transactionsOfSender(mellat), hasLength(3));
    // تکراری ساخته نشد.
    expect((await SmsImporter(store).importAll(inbox)).created, 0);
    expect((await store.getAll()), hasLength(3));
  });

  test('حذفِ دستی بعد از برگشتن، دیگر خودکار برنمی‌گردد', () async {
    await SmsImporter(store).importAll(inbox);
    await c.load();
    await c.removeAllowedSender(c.allowedSenders.single.id, deleteTransactions: true);
    await c.addAllowedSender(mellat, bankId: 'mellat');
    final one = c.transactionsOfSender(mellat).first.id;
    await c.deleteTransaction(one);

    await c.removeAllowedSender(c.allowedSenders.single.id); // فقط برداشتن
    await c.addAllowedSender(mellat, bankId: 'mellat');
    expect(await alive(one), isFalse);
    expect(c.transactionsOfSender(mellat), hasLength(2));
  });

  test('تا فرستنده مجاز نیست یا پیامک با قانون نمی‌خواند، برنمی‌گردد', () async {
    final noId = await store.saveParsed(
        const SmsParser().parse(sender: mellat, body: 'واریز سود\nمبلغ4,033', bankId: 'mellat'),
        sender: mellat,
        receivedAt: now);
    final ok = await save(deposit);
    await store.applyPatches([TxPatch(noId.id, delete: true), TxPatch(ok, delete: true)]);
    await store.setSetting(SettingKeys.autoRemoved, jsonEncode([noId.id, ok]));

    const other = [AllowedSender(id: 'x', address: '+98999')];
    expect(
        planRevival(
            deleted: await store.deletedSmsTransactions(),
            autoRemoved: {noId.id, ok},
            allowed: other),
        isEmpty);

    expect(await c.reviveAutoRemoved(), 1);
    expect(await alive(ok), isTrue);
    expect(await alive(noId.id), isFalse);
    // بی‌شماره در فهرست می‌ماند (شاید پارسرِ بعدی بخواندش)؛ برگشته بیرون می‌رود.
    expect(jsonDecode(store.settings[SettingKeys.autoRemoved]!), [noId.id]);
  });

  test('«برگرداندن»ِ دستی از فهرستِ حذفِ خودکار بیرونش می‌آورد', () async {
    final id = await save(deposit);
    await store.applyPatches([TxPatch(id, delete: true)]);
    await store.setSetting(SettingKeys.autoRemoved, jsonEncode([id]));
    await c.load();
    await c.restoreTransaction((await store.getById(id))!);
    expect(jsonDecode(store.settings[SettingKeys.autoRemoved]!), isEmpty);
  });
}
