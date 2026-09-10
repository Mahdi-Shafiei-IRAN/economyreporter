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

  Future<bool> login(String email, String password) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await repository.login(email: email, password: password);
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
    if (code == 401) return 'ایمیل یا رمز عبور اشتباه است';
    if (code == 400) return 'اطلاعات واردشده معتبر نیست';
    return 'خطا در اتصال به سرور';
  }
}
