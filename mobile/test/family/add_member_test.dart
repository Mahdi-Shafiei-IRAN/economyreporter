import 'package:dio/dio.dart';
import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/features/family/add_member_screen.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

class _FakeFamilyApi implements FamilyApi {
  List<FamilyMember> _members;
  final int? failStatus;
  final Map<String, dynamic>? failBody;
  int addCalls = 0;

  _FakeFamilyApi({
    List<FamilyMember> members = const [FamilyMember(id: 'u-me', name: 'من')],
    this.failStatus,
    this.failBody,
  }) : _members = members;

  @override
  Future<UserProfile> me() async => const UserProfile(id: 'u-me', phone: '09120000001', fullName: 'من');

  @override
  Future<String?> myRole() async => 'owner';

  @override
  Future<List<FamilyMember>> members() async => _members;

  @override
  Future<void> addMember({required String phone, required String password, String? fullName}) async {
    addCalls++;
    if (failStatus != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/family/x/members/invite/'),
        response: Response(requestOptions: RequestOptions(path: '/'), statusCode: failStatus, data: failBody),
      );
    }
    _members = [..._members, FamilyMember(id: 'u-$phone', name: fullName ?? phone)];
  }
}

void main() {
  test('adding a member refreshes the stored member list', () async {
    final store = FakeTransactionStore();
    final api = _FakeFamilyApi();
    final err = await addFamilyMember(api, store, phone: '09120000002', password: 'pass12', fullName: 'مامان');
    expect(err, isNull);
    expect(api.addCalls, 1);
    final members = FamilyMember.decodeList(await store.getSetting(SettingKeys.familyMembers));
    expect(members.map((m) => m.name), contains('مامان'));
  });

  test('a server error becomes a Persian message', () async {
    final api = _FakeFamilyApi(failStatus: 400, failBody: {
      'phone': ['کاربری با این شماره از قبل هست.']
    });
    expect(await addFamilyMember(api, FakeTransactionStore(), phone: '09120000002', password: 'pass12'),
        'کاربری با این شماره از قبل هست.');
  });

  test('forbidden (not the manager)', () async {
    final api = _FakeFamilyApi(failStatus: 403);
    expect(await addFamilyMember(api, FakeTransactionStore(), phone: '09120000002', password: 'pass12'),
        'فقط مدیرِ خانواده می‌تواند عضو اضافه کند');
  });
}
