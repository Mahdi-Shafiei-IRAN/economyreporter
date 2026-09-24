/// به‌روزرسانی درون‌برنامه: نسخه را از سرور می‌خواند، و اگر جدیدتر بود APK را دانلود
/// می‌کند و نصب‌کننده‌ی اندروید را باز می‌کند (بدون فروشگاه).
///
/// دانلود با Dio و در پوشه‌ی موقتِ خودِ برنامه است، پس مجوزِ حافظه لازم ندارد.
/// نسخه‌های ۱٫۰٫۱۷ تا ۱٫۰٫۱۹ با flutter_downloader در پوشه‌ی «دانلودها» ذخیره می‌کردند و
/// همیشه «دانلود ناموفق» می‌دادند. دو دلیل داشت:
///   - لینکِ APK روی http است و دانلودگرِ بومیِ اندروید (برخلافِ Dio) HTTP بی‌رمز را برای
///     دامنه‌ای که در network_security_config نیست رد می‌کند.
///   - نوشتن در «دانلودها» در اندروید ۱۰ به بالا مجوز می‌خواهد.
library;

import 'dart:convert';
import 'dart:io';

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

/// خطای دانلود/نصب با پیامِ فارسیِ قابلِ نمایش.
class UpdateError implements Exception {
  final String message;
  const UpdateError(this.message);

  @override
  String toString() => message;
}

/// پیامِ فارسی برای خطای دانلود/نصب.
String describeUpdateError(Object? e) {
  if (e is UpdateError) return e.message;
  if (e is DioException) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        'اینترنت خیلی کند بود و دانلود نیمه‌کاره ماند. دوباره امتحان کن.',
      DioExceptionType.badResponse =>
        'سرور فایلِ نسخه‌ی جدید را نداد (کد ${e.response?.statusCode}).',
      DioExceptionType.badCertificate => 'گواهیِ امنیتیِ سرور معتبر نبود.',
      _ => 'به سرورِ به‌روزرسانی وصل نشد. اینترنت را بررسی کن.',
    };
  }
  if (e is FileSystemException) {
    return 'فایل روی گوشی ذخیره نشد (${e.osError?.message ?? e.message}). '
        'اگر حافظه‌ی گوشی پر است، کمی جا باز کن.';
  }
  return 'دانلود نشد.';
}

/// نامِ فایل‌هایی که این سرویس در پوشه‌ی موقت می‌سازد (برای پاک کردنِ نسخه‌های قبل).
final _apkFileName = RegExp(r'^economy-.*\.apk(\.part)?$');

class UpdateService {
  final String baseUrl;
  final Dio _dio;
  final Future<Directory> Function() _downloadDir;
  final Future<void> Function(String path) _openInstaller;

  /// [downloadDir] و [openInstaller] فقط برای تست جایگزین می‌شوند.
  UpdateService(
    this.baseUrl, {
    Dio? dio,
    Future<Directory> Function()? downloadDir,
    Future<void> Function(String path)? openInstaller,
  })  : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))),
        _downloadDir = downloadDir ?? getTemporaryDirectory,
        _openInstaller = openInstaller ?? _openWithSystemInstaller;

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

  /// آدرس‌هایی که به ترتیب امتحان می‌شوند: لینکِ version.json، و اگر آن لینک روی
  /// میزبانِ دیگری است (مثلاً دامنه)، همان فایل روی سروری که version.json را داد.
  /// یعنی اگر دامنه در دسترس نبود، دانلود از سرور ادامه پیدا می‌کند.
  List<String> downloadUrls(AppUpdateInfo info) {
    final urls = [info.url];
    final u = Uri.tryParse(info.url), b = Uri.tryParse(baseUrl);
    if (u != null && b != null && u.host != b.host && u.pathSegments.isNotEmpty) {
      urls.add('$baseUrl/${u.pathSegments.last}');
    }
    return urls;
  }

  /// APK را در پوشه‌ی موقتِ برنامه دانلود می‌کند و مسیرش را برمی‌گرداند.
  /// [onProgress] عددی بین ۰ و ۱ می‌گیرد. با لغو، همان DioException ِ لغو پرتاب می‌شود.
  /// هر خطای دیگر به [UpdateError] با پیامِ فارسی تبدیل می‌شود.
  Future<String> downloadApk(
    AppUpdateInfo info, {
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final Directory dir;
    try {
      dir = await _downloadDir();
      await dir.create(recursive: true);
      for (final f in dir.listSync().whereType<File>()) {
        if (!_apkFileName.hasMatch(f.uri.pathSegments.last)) continue;
        try {
          f.deleteSync(); // فایلِ نسخه‌های قبل جا نگیرد
        } catch (_) {}
      }
    } catch (e) {
      throw UpdateError(describeUpdateError(e));
    }
    final safeName = info.versionName.replaceAll(RegExp(r'[^0-9A-Za-z.]'), '');
    final path = '${dir.path}/economy-$safeName.apk';
    final part = '$path.part';

    Object? lastError;
    for (final url in downloadUrls(info)) {
      final sep = url.contains('?') ? '&' : '?';
      try {
        // ضدِکش: پروکسیِ اپراتور نسخه‌ی قدیمیِ فایل را ندهد.
        await _dio.download(
          '$url${sep}_=${DateTime.now().millisecondsSinceEpoch}',
          part,
          cancelToken: cancelToken,
          options: Options(
            headers: {'Cache-Control': 'no-cache'},
            receiveTimeout: const Duration(seconds: 60),
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) onProgress?.call(received / total);
          },
        );
        await _checkIsApk(part);
        await File(part).rename(path);
        return path;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      try {
        final f = File(part);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    throw UpdateError(describeUpdateError(lastError));
  }

  /// APK فایلِ zip است و با «PK» شروع می‌شود. اگر نه، چیزی که رسید صفحه‌ی خطا یا
  /// صفحه‌ی فیلتر بوده، نه برنامه.
  static Future<void> _checkIsApk(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length < 4) throw const UpdateError('فایلِ دانلودشده خالی بود.');
    final head = await file.openRead(0, 2).expand((b) => b).toList();
    if (head[0] != 0x50 || head[1] != 0x4B) {
      throw const UpdateError(
          'چیزی که از سرور رسید فایلِ برنامه نبود (شاید صفحه‌ی خطا یا فیلتر).');
    }
  }

  /// نصب‌کننده‌ی اندروید را برای فایلِ دانلودشده باز می‌کند.
  Future<void> install(String path) => _openInstaller(path);

  /// دانلود و بعد باز کردنِ نصب‌کننده.
  Future<void> downloadAndInstall(
    AppUpdateInfo info, {
    void Function(double)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final path =
        await downloadApk(info, onProgress: onProgress, cancelToken: cancelToken);
    await install(path);
  }
}

Future<void> _openWithSystemInstaller(String path) async {
  final result =
      await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
  switch (result.type) {
    case ResultType.done:
      return;
    case ResultType.permissionDenied:
      throw const UpdateError('اجازه‌ی نصب برای «مالی خانواده» خاموش است. '
          'در تنظیماتِ گوشی «نصب برنامه‌های ناشناس» را برایش روشن کن و دوباره بزن.');
    default:
      throw UpdateError('نصب‌کننده باز نشد: ${result.message}');
  }
}
