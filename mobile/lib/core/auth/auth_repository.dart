/// لایه‌ی احراز هویت: ثبت‌نام/ورود/کاربر جاری + مدیریت توکن.
library;

import 'package:dio/dio.dart';

import '../network/api_client.dart';
import 'token_store.dart';

class UserProfile {
  final String id;
  final String email;
  final String? fullName;

  const UserProfile({required this.id, required this.email, this.fullName});

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'].toString(),
        email: json['email'] as String,
        fullName: json['full_name'] as String?,
      );
}

class AuthRepository {
  final ApiClient api;
  final TokenStore tokenStore;

  AuthRepository(this.api, this.tokenStore);

  Future<void> login({required String email, required String password}) async {
    final resp = await api.dio.post(
      '/auth/login/',
      data: {'email': email, 'password': password},
      options: Options(extra: {'skipAuth': true}),
    );
    await tokenStore.saveTokens(
      access: resp.data['access'] as String,
      refresh: resp.data['refresh'] as String,
    );
  }

  Future<UserProfile> register({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final resp = await api.dio.post(
      '/auth/register/',
      data: {
        'email': email,
        'password': password,
        if (fullName != null) 'full_name': fullName,
      },
      options: Options(extra: {'skipAuth': true}),
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<UserProfile> me() async {
    final resp = await api.dio.get('/auth/me/');
    return UserProfile.fromJson(Map<String, dynamic>.from(resp.data));
  }

  Future<bool> hasSession() async => (await tokenStore.readAccess()) != null;

  Future<void> logout() async => tokenStore.clear();
}
