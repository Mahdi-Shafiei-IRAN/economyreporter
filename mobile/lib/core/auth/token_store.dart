/// ذخیره‌ی امن توکن JWT. اینترفیس تزریق‌پذیر تا در تست بدون گوشی هم کار کند.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStore {
  Future<String?> readAccess();
  Future<String?> readRefresh();
  Future<void> saveTokens({required String access, required String refresh});
  Future<void> clear();
}

/// پیاده‌سازی واقعی روی دستگاه: Android Keystore از طریق flutter_secure_storage.
class SecureTokenStore implements TokenStore {
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';

  final FlutterSecureStorage _storage;

  // در این نسخه، ذخیره‌سازی به‌صورت پیش‌فرض با رمزنگاری پشتیبانِ Keystore انجام می‌شود.
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readAccess() => _storage.read(key: _kAccess);

  @override
  Future<String?> readRefresh() => _storage.read(key: _kRefresh);

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}
