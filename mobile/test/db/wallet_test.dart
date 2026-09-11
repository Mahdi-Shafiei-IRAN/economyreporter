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
  });
  tearDown(() async => db.close());

  test('افزودن و فهرست کیف‌ها', () async {
    await repo.addWallet(const Wallet(
      id: '',
      ownerName: 'بابا',
      label: 'کارت حقوق',
      bankId: 'mellat',
      cardLast4: '1234',
    ));
    final ws = await repo.wallets();
    expect(ws, hasLength(1));
    expect(ws.first.ownerName, 'بابا');
    expect(ws.first.cardLast4, '1234');
    expect(ws.first.id, isNotEmpty);
  });

  test('حذف کیف', () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'مامان', label: 'حساب', accountRef: '00099'));
    final id = (await repo.wallets()).first.id;
    await repo.deleteWallet(id);
    expect(await repo.wallets(), isEmpty);
  });

  test('تطبیق کیف با کارت یا حساب', () {
    const wCard = Wallet(id: 'x', ownerName: 'a', label: 'b', cardLast4: '1234');
    expect(wCard.matches(cardLast4: '1234'), isTrue);
    expect(wCard.matches(cardLast4: '9999'), isFalse);

    const wAcc = Wallet(id: 'y', ownerName: 'a', label: 'b', accountRef: '000123');
    expect(wAcc.matches(accountRef: '000123'), isTrue);
    expect(wAcc.matches(cardLast4: '000123'), isFalse);
  });
}
