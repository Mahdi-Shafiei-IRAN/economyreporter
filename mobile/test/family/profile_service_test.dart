import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

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
  const parser = SmsParser();

  void seedSms(FakeTransactionStore store) => store.seed(
        parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 10,000 ریال از کارت 1234'),
        sender: 'BankMellat',
      );

  test('پروفایل و اعضا ذخیره و تراکنش‌های قبلی به «من» منتسب می‌شوند', () async {
    final store = FakeTransactionStore();
    seedSms(store);
    expect((await store.getAll()).single.ownerUserId, isNull);

    final status = await ProfileService(_FakeFamilyApi(), store).refresh();

    expect(status, ProfileStatus.ok);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-me');
    expect(await store.getSetting(SettingKeys.meName), 'مهدی');
    final members =
        FamilyMember.decodeList(await store.getSetting(SettingKeys.familyMembers));
    expect(members.map((m) => m.name), ['مهدی', 'بابا']);
    expect((await store.getAll()).single.ownerUserId, 'u-me');
  });

  test('کاربرِ بی‌نام با شماره‌اش نشان داده می‌شود', () async {
    final store = FakeTransactionStore();
    await ProfileService(
      _FakeFamilyApi(profile: const UserProfile(id: 'u-me', phone: '09120000001')),
      store,
    ).refresh();
    expect(await store.getSetting(SettingKeys.meName), '09120000001');
  });

  test('آفلاین: وضعیت offline و مقادیر قبلی دست‌نخورده', () async {
    final store = FakeTransactionStore();
    await store.setSetting(SettingKeys.meUserId, 'u-old');
    final status = await ProfileService(_FakeFamilyApi(offline: true), store).refresh();
    expect(status, ProfileStatus.offline);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-old');
  });

  test('عضو عادی: داده‌ی سروریِ بقیه از گوشی پاک می‌شود؛ مالِ خودش می‌ماند', () async {
    final store = FakeTransactionStore();
    final at = DateTime.utc(2026, 9, 10);
    store.addRecord(TransactionRecord(
      id: 'mine', kind: 'expense', amountRial: 1000, ownerUserId: 'u-me',
      origin: 'remote', createdAt: at, updatedAt: at));
    store.addRecord(TransactionRecord(
      id: 'others', kind: 'expense', amountRial: 2000, ownerUserId: 'u-father',
      origin: 'remote', createdAt: at, updatedAt: at));

    await ProfileService(_FakeFamilyApi(role: 'member'), store).refresh();

    final ids = (await store.getAll()).map((t) => t.id).toSet();
    expect(ids, {'mine'});
    expect(await store.getSetting(SettingKeys.myRole), 'member');
  });

  test('مدیر خانواده: داده‌ی بقیه پاک نمی‌شود', () async {
    final store = FakeTransactionStore();
    final at = DateTime.utc(2026, 9, 10);
    store.addRecord(TransactionRecord(
      id: 'others', kind: 'expense', amountRial: 2000, ownerUserId: 'u-father',
      origin: 'remote', createdAt: at, updatedAt: at));

    await ProfileService(_FakeFamilyApi(role: 'owner'), store).refresh();

    expect((await store.getAll()).map((t) => t.id), contains('others'));
    expect(await store.getSetting(SettingKeys.myRole), 'owner');
  });

  test('حسابِ قدیمیِ بی‌شماره (ایمیلی): باید دوباره با شماره وارد شد', () async {
    final store = FakeTransactionStore();
    await store.setSetting(SettingKeys.meUserId, 'u-test');
    final status = await ProfileService(
      _FakeFamilyApi(profile: const UserProfile(id: 'u-test', phone: '', fullName: 'کاربر تست')),
      store,
    ).refresh();

    expect(status, ProfileStatus.needsRelogin);
    expect(await store.getSetting(SettingKeys.meName), isNull); // چیزی از آن حساب ذخیره نشد
  });

  test('ورود با حساب دیگر: داده‌ی خانواده‌ی قبلی پاک و کارت‌های «من» به کاربر جدید',
      () async {
    final store = FakeTransactionStore();
    store.settings[SettingKeys.meUserId] = 'u-test';
    store.settings[SettingKeys.pullCursor] = '2026-09-11T00:00:00Z|x';
    await store.addWallet(const Wallet(
        id: '', ownerName: 'کاربر تست', ownerUserId: 'u-test', label: 'کارت من', cardLast4: '1234'));
    seedSms(store);
    store.addRecord(TransactionRecord(
      id: 'remote-1',
      kind: 'expense',
      amountRial: 5000,
      ownerUserId: 'u-other',
      ownerName: 'کاربر تست',
      origin: 'remote',
      createdAt: DateTime.utc(2026, 9, 10),
      updatedAt: DateTime.utc(2026, 9, 10),
    ));

    final status = await ProfileService(_FakeFamilyApi(), store).refresh();

    expect(status, ProfileStatus.ok);
    final all = await store.getAll();
    expect(all.map((t) => t.id), isNot(contains('remote-1')));
    expect(all.single.ownerUserId, 'u-me');
    expect(all.single.ownerName, 'مهدی');
    final wallet = (await store.wallets()).single;
    expect(wallet.ownerUserId, 'u-me');
    expect(wallet.ownerName, 'مهدی');
    expect(await store.getSetting(SettingKeys.pullCursor), isNull);
  });
}
