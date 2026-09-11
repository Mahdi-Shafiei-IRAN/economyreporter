import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

/// پیامک‌های واقعیِ بانک‌ها شماره‌ی کارت ندارند (حساب دارند یا هیچ). کارتی که کاربر با
/// ۴ رقم کارت یا فقط با بانک ثبت می‌کند باید باز هم صاحبِ تراکنش‌ها را تعیین کند.
void main() {
  late Database db;
  late TransactionRepository repo;
  late SmsImporter importer;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
    importer = SmsImporter(repo);
    await repo.addAllowedSender('BankMellat', bankId: 'mellat');
    await repo.addAllowedSender('Blu', bankId: 'blu');
  });

  tearDown(() async => db.close());

  const accountSms = 'حساب1000000001\nبرداشت12,345,000\nمانده6,000,000\n05/06/19-16:00';
  const bluSms = 'بلو\nخرید 250,000 ریال\nمانده 1,000,000';

  Future<String?> importOwner(String sender, String body) async {
    final tx = await importer.importOne(
        RawSms(sender: sender, body: body, receivedAt: DateTime.utc(2026, 9, 10)));
    return (await repo.getById(tx!.id))!.ownerName;
  }

  test('پیامکِ حساب‌محور به کارتی می‌رسد که با ۴ رقم کارت ثبت شده', () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'بابا', label: 'کارت ملت', bankId: 'mellat', cardLast4: '1234'));
    expect(await importOwner('BankMellat', accountSms), 'بابا');
  });

  test('پیامکِ بی‌شماره به کارتی می‌رسد که فقط با بانک ثبت شده', () async {
    await repo.addWallet(
        const Wallet(id: '', ownerName: 'مامان', label: 'حساب بلو', bankId: 'blu'));
    expect(await importOwner('Blu', bluSms), 'مامان');
  });

  test('تعیین صاحب بعد از رسیدن پیامک‌ها: تراکنش‌های قبلی هم به همان کارت می‌روند',
      () async {
    expect(await importOwner('Blu', bluSms), isNull);
    await repo.addWallet(
        const Wallet(id: '', ownerName: 'مامان', label: 'حساب بلو', bankId: 'blu'));
    expect((await repo.getAll()).single.ownerName, 'مامان');
  });

  test('کارتِ دیگرِ همان بانک (شماره‌ی کارتِ متفاوت) اشتباهی انتخاب نمی‌شود', () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'بابا', label: 'ملت', bankId: 'mellat', cardLast4: '1234'));
    expect(await importOwner('BankMellat', 'خرید مبلغ 50,000 ریال از کارت 9999'), isNull);
  });

  test('دو کارتِ یک بانک: نامعلوم، مگر یکی «فقط بانک» (برای پیامک‌های بی‌شماره) باشد',
      () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'بابا', label: 'ملت ۱', bankId: 'mellat', cardLast4: '1234'));
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'مامان', label: 'ملت ۲', bankId: 'mellat', cardLast4: '5678'));
    expect(await importOwner('BankMellat', accountSms), isNull);

    await repo.addWallet(
        const Wallet(id: '', ownerName: 'مهدی', label: 'پیامک‌های ملت', bankId: 'mellat'));
    expect((await repo.getAll()).single.ownerName, 'مهدی');
  });
}
