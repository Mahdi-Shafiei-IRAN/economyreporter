/// به‌روزرسانی درون‌برنامه: نسخه را از سرور می‌خواند، و در صورت جدیدتر بودن APK را
/// دانلود (پس‌زمینه با WorkManager) و نصب می‌کند (بدون فروشگاه).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

/// مقایسه‌ی نامِ نسخه‌ی معنایی («1.0.9» با «1.0.10»). خروجی: مثبت اگر a>b.
int compareVersionNames(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .split('.')
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

bool isUpdateAvailable(String currentName, AppUpdateInfo? info) =>
    info != null &&
    info.url.isNotEmpty &&
    compareVersionNames(info.versionName, currentName) > 0;

/// پوشه دانلودهای عمومی اندروید.
const _kDownloadsPath = '/storage/emulated/0/Download';

/// نام ثابت فایل APK دانلودشده (هر بار بازنویسی می‌شود).
const _kApkFilename = 'economy-update.apk';

class UpdateService {
  final String baseUrl;
  final Dio _dio;

  UpdateService(this.baseUrl, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));

  Future<int> currentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<String> currentVersionName() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  Future<AppUpdateInfo?> fetch() async {
    try {
      final resp = await _dio.get('$baseUrl/version.json',
          queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
          options: Options(
            responseType: ResponseType.json,
            headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          ));
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

  Future<AppUpdateInfo?> check() async {
    final info = await fetch();
    if (info == null) return null;
    return isUpdateAvailable(await currentVersionName(), info) ? info : null;
  }

  /// دانلود APK در پس‌زمینه با WorkManager (صفحه خاموش = دانلود ادامه دارد).
  /// APK در پوشه «دانلودها» ذخیره می‌شود.
  /// برمی‌گرداند: taskId برای پیگیری وضعیت از طریق callback.
  Future<String?> startBackgroundDownload(AppUpdateInfo info) async {
    // حذف نسخه قبلی اگر هست (تا نام فایل ثابت بماند).
    final tasks = await FlutterDownloader.loadTasksWithRawQuery(
      query: "SELECT * FROM task WHERE file_name='$_kApkFilename'",
    );
    for (final t in tasks ?? []) {
      await FlutterDownloader.remove(taskId: t.taskId, shouldDeleteContent: true);
    }

    final sep = info.url.contains('?') ? '&' : '?';
    final url = '${info.url}${sep}_=${DateTime.now().millisecondsSinceEpoch}';

    return FlutterDownloader.enqueue(
      url: url,
      headers: {'Cache-Control': 'no-cache'},
      savedDir: _kDownloadsPath,
      fileName: _kApkFilename,
      showNotification: true,
      openFileFromNotification: true,
      requiresStorageNotLow: false,
    );
  }

  /// مسیر کامل فایل APK دانلودشده.
  String get downloadedApkPath => '$_kDownloadsPath/$_kApkFilename';

  /// باز کردن نصب‌کننده برای فایل APK.
  Future<void> installApk() async {
    final result = await OpenFilex.open(
      downloadedApkPath,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
