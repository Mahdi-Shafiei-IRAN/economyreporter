import 'package:dio/dio.dart';
import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
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
  Future<UserProfile> me() async =>
      const UserProfile(id: 'u-me', phone: '09120000001', fullName: 'من');

  @override
  Future<String?> myRole() async => 'owner';

  @override
  Future<List<FamilyMember>> members() async => _members;

  @override
  Future<void> addMember({
    required String phone,
    required String password,
    String? fullName,
  }) async {
    addCalls++;
    if (failStatus != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/family/x/members/invite/'),
        response: Response(
          requestOptions: RequestOptions(path: '/'),
          statusCode: failStatus,
          data: failBody,
        ),
      );
    }
    _members = [..._members, FamilyMember(id: 'u-$phone', name: fullName ?? phone)];
  }
}

Future<DashboardController> _controller(
  FakeTransactionStore store,
  FamilyApi api, {
  String role = 'owner',
}) async {
  await store.setSetting(SettingKeys.myRole, role);
  await store.setSetting(
    SettingKeys.familyMembers,
    FamilyMember.encodeList(await api.members()),
  );
  final c = DashboardController(store, familyApi: api);
  await c.load();
  return c;
}

void main() {
  test('مدیر می‌تواند عضو اضافه کند (بدون سقف)', () async {
    final store = FakeTransactionStore();
    final api = _FakeFamilyApi();
    final c = await _controller(store, api);

    expect(c.canAddMember, isTrue);
    final err = await c.addMember(phone: '09120000002', password: 'pass12', fullName: 'مامان');
    expect(err, isNull);
    expect(api.addCalls, 1);
    expect(c.members.map((m) => m.name), contains('مامان'));
  });

  test('عضوِ عادی نمی‌تواند عضو اضافه کند', () async {
    final store = FakeTransactionStore();
    final api = _FakeFamilyApi();
    final c = await _controller(store, api, role: 'member');
    expect(c.canAddMember, isFalse);
  });

  test('حتی با چند عضو، مدیر باز هم می‌تواند اضافه کند (سقف برداشته شد)', () async {
    final store = FakeTransactionStore();
    final api = _FakeFamilyApi(members: const [
      FamilyMember(id: 'a', name: 'یک'),
      FamilyMember(id: 'b', name: 'دو'),
      FamilyMember(id: 'c', name: 'سه'),
    ]);
    final c = await _controller(store, api);
    expect(c.canAddMember, isTrue);
  });

  test('خطای سرور به پیام فارسی تبدیل می‌شود', () async {
    final store = FakeTransactionStore();
    final api = _FakeFamilyApi(failStatus: 400, failBody: {
      'phone': ['کاربری با این شماره از قبل هست.']
    });
    final c = await _controller(store, api);
    final err = await c.addMember(phone: '09120000002', password: 'pass12');
    expect(err, 'کاربری با این شماره از قبل هست.');
  });
}
