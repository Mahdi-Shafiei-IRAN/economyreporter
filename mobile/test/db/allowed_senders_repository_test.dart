import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

void main() {
  late Database db;
  late AppStore repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = AppStore(db);
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
}
