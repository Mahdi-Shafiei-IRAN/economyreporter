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
    final name = (user['full_name'] as String?)?.trim();
    return FamilyMember(
      id: user['id'].toString(),
      name: (name == null || name.isEmpty) ? user['email'].toString() : name,
    );
  }
}

/// پروفایل و اعضا را از سرور می‌گیرد و در تنظیمات محلی نگه می‌دارد (برای آفلاین).
class ProfileService {
  final FamilyApi api;
  final TransactionStore store;

  ProfileService(this.api, this.store);

  /// در حالت آفلاین بی‌صدا false برمی‌گرداند و مقادیر قبلی می‌مانند.
  Future<bool> refresh() async {
    try {
      final me = await api.me();
      final name = (me.fullName == null || me.fullName!.trim().isEmpty)
          ? me.email
          : me.fullName!.trim();
      final previous = await store.getSetting(SettingKeys.meUserId);
      await store.setSetting(SettingKeys.meUserId, me.id);
      await store.setSetting(SettingKeys.meName, name);
      try {
        final members = await api.members();
        await store.setSetting(
            SettingKeys.familyMembers, FamilyMember.encodeList(members));
      } catch (_) {
        // اعضا بعداً دوباره گرفته می‌شوند
      }
      if (previous != me.id) await store.reattributeLocal();
      return true;
    } catch (_) {
      return false;
    }
  }
}
