/// اعضای خانواده (کاربران سرور) و پروفایل کاربر جاری.
///
/// شناسه‌ی کاربر جاری لازم است تا معلوم شود کدام تراکنش‌ها «مال من» است
/// (قابل ویرایش) و کدام مال عضو دیگر (فقط دیدنی).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../../features/transactions/data/transaction_repository.dart';
import '../auth/auth_repository.dart';

class FamilyMember {
  final String id;
  final String name;

  const FamilyMember({required this.id, required this.name});

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory FamilyMember.fromJson(Map<String, dynamic> j) =>
      FamilyMember(id: j['id'].toString(), name: (j['name'] ?? '').toString());

  static List<FamilyMember> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => FamilyMember.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<FamilyMember> members) =>
      jsonEncode([for (final m in members) m.toJson()]);
}

abstract class FamilyApi {
  Future<UserProfile> me();
  Future<List<FamilyMember>> members();
}

class DioFamilyApi implements FamilyApi {
  final Dio dio;

  DioFamilyApi(this.dio);

  @override
  Future<UserProfile> me() async {
    final resp = await dio.get('/auth/me/');
    return UserProfile.fromJson(Map<String, dynamic>.from(resp.data as Map));
  }

  @override
  Future<List<FamilyMember>> members() async {
    final families = (await dio.get('/family/')).data as List? ?? const [];
    if (families.isEmpty) return const [];
    final familyId = (families.first as Map)['id'].toString();
    final resp = await dio.get('/family/$familyId/members/');
    return [
      for (final m in (resp.data as List))
        _memberFromUser(Map<String, dynamic>.from((m as Map)['user'] as Map)),
    ];
  }

  static FamilyMember _memberFromUser(Map<String, dynamic> user) {
    final profile = UserProfile.fromJson(user);
    return FamilyMember(id: profile.id, name: profile.displayName);
  }
}

/// نتیجه‌ی گرفتن پروفایل از سرور.
enum ProfileStatus {
  ok,

  /// سرور در دسترس نبود؛ مقادیر قبلی می‌مانند.
  offline,

  /// حسابِ قدیمیِ بی‌شماره (ورود با ایمیل)؛ باید با شماره‌ی موبایل دوباره وارد شد.
  needsRelogin,
}

/// پروفایل و اعضا را از سرور می‌گیرد و در تنظیمات محلی نگه می‌دارد (برای آفلاین).
class ProfileService {
  final FamilyApi api;
  final TransactionStore store;

  ProfileService(this.api, this.store);

  Future<ProfileStatus> refresh() async {
    final UserProfile me;
    try {
      me = await api.me();
    } catch (_) {
      return ProfileStatus.offline;
    }
    if (me.phone.trim().isEmpty) return ProfileStatus.needsRelogin;

    List<FamilyMember>? members;
    try {
      members = await api.members();
    } catch (_) {
      // اعضا بعداً دوباره گرفته می‌شوند
    }
    final previous = await store.getSetting(SettingKeys.meUserId);
    if (previous != null && previous != me.id) {
      // حساب دیگری روی همین گوشی وارد شد (مثلاً از «کاربر تست» به حساب واقعی).
      await store.switchAccount(
        previousUserId: previous,
        userId: me.id,
        userName: me.displayName,
        memberIds: members?.map((m) => m.id).toSet(),
      );
    }
    await store.setSetting(SettingKeys.meUserId, me.id);
    await store.setSetting(SettingKeys.meName, me.displayName);
    if (members != null) {
      await store.setSetting(
          SettingKeys.familyMembers, FamilyMember.encodeList(members));
    }
    if (previous != me.id) await store.reattributeLocal();
    return ProfileStatus.ok;
  }
}
