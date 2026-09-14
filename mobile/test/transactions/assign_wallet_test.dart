import 'package:economy/core/database/app_database.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

void main() {
  late Database db;
  late TransactionRepository repo;

  setUpAll(initSqfliteFfiForTests);
  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
    await repo.setSetting(SettingKeys.meUserId, 'u-me');
  });
  tearDown(() async => db.close());

  test('انتسابِ دستی پایدار می‌ماند و با reattribute بازنویسی نمی‌شود', () async {
    // دو کیفِ بی‌شماره در یک بانک (ابهام: خودکار نمی‌تواند تفکیک کند).
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'من', ownerUserId: 'u-me', label: 'حساب حقوق', bankId: 'mellat'));
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'من', ownerUserId: 'u-me', label: 'حساب پس‌انداز', bankId: 'mellat'));

    final txId = await repo.addManual(
        kind: 'expense', amountRial: 500000, at: DateTime.utc(2026, 9, 10), bankId: 'mellat');

    final savings = (await repo.wallets()).firstWhere((w) => w.label == 'حساب پس‌انداز');
    await repo.assignWalletToTransaction(txId, savings);

    var rec = await repo.getById(txId);
    expect(rec!.walletLabel, 'حساب پس‌انداز');

    // reattribute نباید انتسابِ دستی را عوض کند
    await repo.reattributeLocal();
    rec = await repo.getById(txId);
    expect(rec!.walletLabel, 'حساب پس‌انداز');
  });

  test('برداشتن pin → برگشت به حالت خودکار', () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'من', ownerUserId: 'u-me', label: 'حساب حقوق', bankId: 'mellat'));
    final txId = await repo.addManual(
        kind: 'expense', amountRial: 500000, at: DateTime.utc(2026, 9, 10), bankId: 'mellat');
    final w = (await repo.wallets()).single;
    await repo.assignWalletToTransaction(txId, w);
    await repo.clearWalletPin(txId);
    // بعد از clear، فقط یک کیفِ هم‌بانک هست پس خودکار همان را می‌گیرد
    final rec = await repo.getById(txId);
    expect(rec!.walletLabel, 'حساب حقوق');
  });
}
