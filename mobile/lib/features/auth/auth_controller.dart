/// کنترلر وضعیت احراز هویت.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/auth/auth_repository.dart';

class AuthController extends ChangeNotifier {
  final AuthRepository repository;

  bool authenticated = false;
  bool loading = false;
  String? error;

  AuthController(this.repository);

  Future<void> bootstrap() async {
    authenticated = await repository.hasSession();
    notifyListeners();
  }

  Future<bool> login(String phone, String password) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repository.login(phone: phone, password: password);
      authenticated = true;
      return true;
    } on DioException catch (e) {
      error = _messageFor(e);
      return false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await repository.logout();
    authenticated = false;
    notifyListeners();
  }

  String _messageFor(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401) return 'شماره موبایل یا رمز عبور اشتباه است';
    if (code == 400) return 'شماره موبایل و رمز را کامل وارد کن';
    if (code == 429) return 'تلاش زیاد بود؛ یک دقیقه صبر کن و دوباره بزن';
    return 'خطا در اتصال به سرور';
  }
}
