/// لایه‌ی احراز هویت: ورود با شماره موبایل + رمز، کاربر جاری و مدیریت توکن.
/// ثبت‌نام در اپ نداریم؛ کاربرها را مدیر در پنل ادمین سرور می‌سازد.
library;

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import '../sms/digit_utils.dart';
import 'token_store.dart';

class UserProfile {
  final String id;
  final String phone;
  final String? fullName;

  const UserProfile({required this.id, required this.phone, this.fullName});

  /// نام نمایشی: نام کامل، وگرنه شماره.
  String get displayName {
    final name = fullName?.trim();
    return (name == null || name.isEmpty) ? phone : name;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'].toString(),
        phone: (json['phone'] ?? '').toString(),
        fullName: json['full_name'] as String?,
      );
}

class AuthRepository {
  final ApiClient api;
  final TokenStore tokenStore;

  AuthRepository(this.api, this.tokenStore);

  /// [phone] به هر شکلی (ارقام فارسی، +98، بدون صفر) پذیرفته می‌شود؛ سرور
  /// آن را استاندارد می‌کند.
  Future<void> login({required String phone, required String password}) async {
    final resp = await api.dio.post(
      '/auth/login/',
      data: {'phone': normalizeDigits(phone.trim()), 'password': password},
      options: Options(extra: {'skipAuth': true}),
    );
    await tokenStore.saveTokens(
      access: resp.data['access'] as String,
      refresh: resp.data['refresh'] as String,
    );
  }

  /// ثبت‌نامِ آزاد: حساب و خانواده‌ی تازه می‌سازد و بلافاصله وارد می‌شود.
  Future<void> register({
    required String phone,
    required String password,
    String? fullName,
    String? familyName,
  }) async {
    final resp = await api.dio.post(
      '/auth/register/',
      data: {
        'phone': normalizeDigits(phone.trim()),
        'password': password,
        if (fullName != null && fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
        if (familyName != null && familyName.trim().isNotEmpty)
          'family_name': familyName.trim(),
      },
      options: Options(extra: {'skipAuth': true}),
    );
    await tokenStore.saveTokens(
      access: resp.data['access'] as String,
      refresh: resp.data['refresh'] as String,
    );
  }

  Future<UserProfile> me() async {
    final resp = await api.dio.get('/auth/me/');
    return UserProfile.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<bool> hasSession() async => (await tokenStore.readAccess()) != null;

  Future<void> logout() async => tokenStore.clear();
}
