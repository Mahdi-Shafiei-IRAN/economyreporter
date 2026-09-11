import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

class _FakeFamilyApi implements FamilyApi {
  bool offline;
  String? fullName;
  _FakeFamilyApi({this.offline = false, this.fullName = 'مهدی'});

  @override
  Future<UserProfile> me() async {
    if (offline) throw Exception('offline');
    return UserProfile(id: 'u-me', phone: '09120000001', fullName: fullName);
  }

  @override
  Future<List<FamilyMember>> members() async => const [
        FamilyMember(id: 'u-me', name: 'مهدی'),
        FamilyMember(id: 'u-father', name: 'بابا'),
      ];
}

void main() {
  test('پروفایل و اعضا ذخیره و تراکنش‌های قبلی به «من» منتسب می‌شوند', () async {
    final store = FakeTransactionStore();
    store.seed(
      const SmsParser().parse(
          sender: 'BankMellat', body: 'خرید مبلغ 10,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );
    expect((await store.getAll()).single.ownerUserId, isNull);

    final ok = await ProfileService(_FakeFamilyApi(), store).refresh();

    expect(ok, isTrue);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-me');
    expect(await store.getSetting(SettingKeys.meName), 'مهدی');
    final members =
        FamilyMember.decodeList(await store.getSetting(SettingKeys.familyMembers));
    expect(members.map((m) => m.name), ['مهدی', 'بابا']);
    expect((await store.getAll()).single.ownerUserId, 'u-me');
  });

  test('کاربرِ بی‌نام با شماره‌اش نشان داده می‌شود', () async {
    final store = FakeTransactionStore();
    await ProfileService(_FakeFamilyApi(fullName: ''), store).refresh();
    expect(await store.getSetting(SettingKeys.meName), '09120000001');
  });

  test('آفلاین: false و مقادیر قبلی دست‌نخورده', () async {
    final store = FakeTransactionStore();
    await store.setSetting(SettingKeys.meUserId, 'u-old');
    final ok = await ProfileService(_FakeFamilyApi(offline: true), store).refresh();
    expect(ok, isFalse);
    expect(await store.getSetting(SettingKeys.meUserId), 'u-old');
  });
}
