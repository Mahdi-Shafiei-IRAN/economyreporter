/// به‌روزرسانی درون‌برنامه: نسخه را از سرور می‌خواند، و در صورت جدیدتر بودن APK را
/// دانلود و نصب می‌کند (بدون فروشگاه). فرمت version.json روی سرور:
///   {"versionCode": 3, "versionName": "1.0.2", "notes": "...", "url": ".../economy-latest.apk"}
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final int versionCode;
  final String versionName;
  final String notes;
  final String url;

  const AppUpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.notes,
    required this.url,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> j, {required String base}) {
    var url = (j['url'] ?? '').toString();
    if (url.isNotEmpty && !url.startsWith('http')) {
      url = '$base/${url.replaceFirst(RegExp(r'^/'), '')}';
    }
    return AppUpdateInfo(
      versionCode: (j['versionCode'] as num?)?.toInt() ?? 0,
      versionName: (j['versionName'] ?? '').toString(),
      notes: (j['notes'] ?? '').toString(),
      url: url,
    );
  }
}

/// آیا نسخه‌ی سرور از نسخه‌ی نصب‌شده جدیدتر است؟ (منطق خالص و تست‌پذیر)
bool isUpdateAvailable(int currentCode, AppUpdateInfo? info) =>
    info != null && info.url.isNotEmpty && info.versionCode > currentCode;

class UpdateService {
  /// ریشه‌ی فایل‌های به‌روزرسانی (مثل http://server/updates).
  final String baseUrl;
  final Dio _dio;

  UpdateService(this.baseUrl, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  /// نسخه‌ی فعلیِ نصب‌شده (versionCode / build number).
  Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// نسخه‌ی روی سرور را می‌خواند (بدون مقایسه)؛ null یعنی سرور در دسترس نبود.
  Future<AppUpdateInfo?> fetch() async {
    try {
      final resp = await _dio.get('$baseUrl/version.json',
          options: Options(responseType: ResponseType.json));
      final data = resp.data is Map
          ? Map<String, dynamic>.from(resp.data as Map)
          : (resp.data is String
              ? Map<String, dynamic>.from(jsonDecode(resp.data as String) as Map)
              : <String, dynamic>{});
      return AppUpdateInfo.fromJson(data, base: baseUrl);
    } catch (_) {
      return null;
    }
  }

  /// اگر نسخه‌ی جدیدتری هست برمی‌گرداند؛ در آفلاین یا نبودِ سرور، null (بی‌صدا).
  Future<AppUpdateInfo?> check() async {
    final info = await fetch();
    if (info == null) return null;
    return isUpdateAvailable(await currentVersionCode(), info) ? info : null;
  }

  /// APK را دانلود و نصب را باز می‌کند. [onProgress] بین 0 و 1.
  Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    void Function(double)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = '${dir.path}/economy-${info.versionCode}.apk';
    await _dio.download(
      info.url,
      file,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    // نصب‌کننده‌ی سیستم را با فایل باز می‌کند (نیازمند اجازه‌ی «نصب برنامه»).
    final result = await OpenFilex.open(file, type: 'application/vnd.android.package-archive');
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
