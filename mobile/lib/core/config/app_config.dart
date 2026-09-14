/// تنظیمات اپ. آدرس API با --dart-define=API_BASE_URL=... قابل override است.
library;

class AppConfig {
  /// گوشی واقعی روی Wi-Fi: IP کامپیوترِ سرور. اگر IP کامپیوتر عوض شد،
  /// این مقدار را عوض کن یا موقع بیلد با --dart-define=API_BASE_URL=... بده.
  /// (امولاتور اندروید: به‌جای IP از 10.0.2.2 استفاده کن.)
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.100:8000/api/v1',
  );

  /// ریشه‌ی فایل‌های به‌روزرسانی روی سرور (version.json و APK)، از روی apiBaseUrl.
  static String get updatesBaseUrl =>
      "${apiBaseUrl.replaceFirst(RegExp(r'/api/v1/?$'), '')}/updates";
}
