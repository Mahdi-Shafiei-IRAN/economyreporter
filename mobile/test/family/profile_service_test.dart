import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

class _FakeFamilyApi implements FamilyApi {
  bool offline;
  UserProfile profile;
  String role;

  _FakeFamilyApi({
    this.offline = false,
    this.profile = const UserProfile(id: 'u-me', phone: '09120000001', fullName: 'مهدی'),
    this.role = 'owner',
  });

  @override
  Future<UserProfile> me() async {
    if (offline) throw Exception('offline');
    return profile;
  }

  @override
  Future<String?> myRole() async => role;

  @override
  Future<void> addMember({
    required String phone,
    required String password,
    String? fullName,
  }) async {}

  @override
  Future<List<FamilyMember>> members() async => const [
        FamilyMember(id: 'u-me', name: 'مهدی'),
        FamilyMember(id: 'u-father', name: 'بابا'),
      ];
}

void main() {
  late Database db;
  late AppStore store;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    store = AppStore(db);
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>> wallet(String id) async =>
      (await db.query('wallets', where: 'id = ?', whereArgs: [id])).single;

  Future<void> addWallet(String id, String? owner, String ownerName) => db.insert('wallets', {
        'id': id,
        'owner_user_id': owner,
        'owner_name': ownerName,
        'label': id,
        'created_at': '2026-09-01T00:00:00Z',
      });

  test('پروفایل، نقش و اعضا ذخیره می‌شوند', () async {
    final status = await ProfileService(_FakeFamilyApi(), store).refresh();

    expect(status, ProfileStatus.ok);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-me');
    expect(await store.getSetting(SettingKeys.meName), 'مهدی');
    expect(await store.getSetting(SettingKeys.myRole), 'owner');
    final members = FamilyMember.decodeList(await store.getSetting(SettingKeys.familyMembers));
    expect(members.map((m) => m.name), ['مهدی', 'بابا']);
  });

  test('کاربرِ بی‌نام با شماره‌اش نشان داده می‌شود', () async {
    final api = _FakeFamilyApi(profile: const UserProfile(id: 'u-me', phone: '09120000001'));
    await ProfileService(api, store).refresh();
    expect(await store.getSetting(SettingKeys.meName), '09120000001');
  });

  test('آفلاین: وضعیت offline و مقادیر قبلی دست‌نخورده', () async {
    await store.setSetting(SettingKeys.meUserId, 'u-old');
    final status = await ProfileService(_FakeFamilyApi(offline: true), store).refresh();
    expect(status, ProfileStatus.offline);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-old');
  });

  test('عضو عادی: نقش ذخیره می‌شود', () async {
    await ProfileService(_FakeFamilyApi(role: 'member'), store).refresh();
    expect(await store.getSetting(SettingKeys.myRole), 'member');
  });

  test('حسابِ قدیمیِ بی‌شماره (ایمیلی): باید دوباره با شماره وارد شد', () async {
    final api = _FakeFamilyApi(profile: const UserProfile(id: 'u-old', phone: '', fullName: 'قدیمی'));
    final status = await ProfileService(api, store).refresh();
    expect(status, ProfileStatus.needsRelogin);
    expect(await store.getSetting(SettingKeys.meName), isNull); // چیزی از آن حساب ذخیره نشد
  });

  test('ورود با حساب دیگر: کارت‌های «من» به کاربرِ تازه، کارتِ غریبه بی‌صاحب، cursorها از نو', () async {
    await store.setSetting(SettingKeys.meUserId, 'u-test');
    await store.setSetting(SettingKeys.walletCursor, '2026-09-11T00:00:00Z|x');
    await store.setSetting(SettingKeys.budgetCursor, '2026-09-11T00:00:00Z|y');
    await addWallet('mine', 'u-test', 'کاربر تست');
    await addWallet('dad', 'u-father', 'بابا');
    await addWallet('stranger', 'u-stranger', 'غریبه');

    final status = await ProfileService(_FakeFamilyApi(), store).refresh();

    expect(status, ProfileStatus.ok);
    expect((await wallet('mine'))['owner_user_id'], 'u-me');
    expect((await wallet('mine'))['owner_name'], 'مهدی');
    expect((await wallet('dad'))['owner_user_id'], 'u-father'); // عضوِ خانواده‌ی تازه
    expect((await wallet('stranger'))['owner_user_id'], isNull);
    expect(await store.getSetting(SettingKeys.walletCursor), isNull);
    expect(await store.getSetting(SettingKeys.budgetCursor), isNull);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-me');
  });
}
