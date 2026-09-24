import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

/// ورود با حساب دیگری روی همان گوشی (مثلاً از «کاربر تست» به حساب واقعی).
void main() {
  late Database db;
  late TransactionRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
  });

  tearDown(() async => db.close());

  test('داده‌ی خانواده‌ی قبلی پاک؛ پیامک‌های این گوشی با شناسه‌ی تازه برای خانواده‌ی جدید صف',
      () async {
    await repo.setSetting(SettingKeys.meUserId, 'u-test');
    await repo.setSetting(SettingKeys.pullCursor, '2026-09-11T00:00:00Z|x');
    await repo.addAllowedSender('BankMellat', bankId: 'mellat');
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'کاربر تست', ownerUserId: 'u-test', label: 'کارت من', bankId: 'mellat'));
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'غریبه', ownerUserId: 'u-stranger', label: 'کارت دیگر', cardLast4: '9999'));

    final imported = await SmsImporter(repo).importOne(RawSms(
      sender: 'BankMellat',
      body: 'خرید مبلغ 50,000 ریال از کارت 1234',
      receivedAt: DateTime.utc(2026, 9, 10),
    ));
    final fruit = (await repo.categories()).firstWhere((c) => c.name == 'میوه');
    await repo.categorize(imported!.id, [fruit.id]);
    await db.delete('outbox'); // قبلاً برای خانواده‌ی قبلی ارسال شده بود
    await repo.applyRemote({
      'id': 'remote-1',
      'kind': 'expense',
      'amount_rial': 1000,
      'owner': 'u-other',
      'owner_name': 'کاربر تست',
      'updated_at': '2026-09-10T00:00:00Z',
    });

    await repo.switchAccount(
      previousUserId: 'u-test',
      userId: 'u-new',
      userName: 'مهدی',
      memberIds: {'u-new', 'u-ali'},
    );

    final all = await repo.getAll();
    expect(all.map((t) => t.id), isNot(contains('remote-1')));
    final mine = all.single;
    // سرور شناسه‌ی قبلی را در خانواده‌ی قبلی دارد؛ شناسه‌ی تازه تا «تعارض شناسه» نشود.
    expect(mine.id, isNot(imported.id));
    expect(mine.allocations.single.categoryName, 'میوه');
    expect(await repo.pendingSyncCount(), 1);

    final wallets = await repo.wallets();
    final myCard = wallets.firstWhere((w) => w.label == 'کارت من');
    expect(myCard.ownerUserId, 'u-new');
    expect(myCard.ownerName, 'مهدی');
    expect(wallets.firstWhere((w) => w.label == 'کارت دیگر').ownerUserId, isNull);
    expect(await repo.getSetting(SettingKeys.pullCursor), isNull);
  });
}
