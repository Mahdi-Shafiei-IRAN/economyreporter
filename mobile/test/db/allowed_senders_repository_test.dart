import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
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

  tearDown(() async {
    await db.close();
  });

  test('فرستنده‌ی مجاز ذخیره می‌شود؛ همان فرستنده با شکل دیگر دوباره اضافه نمی‌شود',
      () async {
    final a = await repo.addAllowedSender(' +98200012345 ', bankId: 'tejarat');
    final again = await repo.addAllowedSender('0200012345');

    expect(again.id, a.id);
    final list = await repo.allowedSenders();
    expect(list, hasLength(1));
    expect(list.single.address, '+98200012345');
    expect(list.single.bankId, 'tejarat');

    await repo.deleteAllowedSender(a.id);
    expect(await repo.allowedSenders(), isEmpty);
  });

  test('مجاز کردن فرستنده با بانک: پیامک‌های قبلیِ بی‌بانکِ همان فرستنده بانک می‌گیرند',
      () async {
    const parser = SmsParser();
    await repo.saveParsed(
      parser.parse(sender: '+98300045', body: 'برداشت مبلغ 80,000 ریال'),
      sender: '+98300045',
      receivedAt: DateTime.utc(2026, 9, 1),
    );
    expect((await repo.getAll()).single.bankId, isNull);

    await repo.addAllowedSender('0300045', bankId: 'refah');

    expect((await repo.getAll()).single.bankId, 'refah');
  });
}
