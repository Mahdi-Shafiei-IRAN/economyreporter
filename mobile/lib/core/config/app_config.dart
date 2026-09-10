/// تنظیمات اپ. آدرس API با --dart-define=API_BASE_URL=... قابل override است.
library;

class AppConfig {
  /// امولاتور اندروید: `10.0.2.2` یعنی localhostِ کامپیوترِ میزبان.
  /// گوشی واقعی روی Wi-Fi: IP کامپیوتر، مثلاً http://192.168.1.23:8000/api/v1
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
