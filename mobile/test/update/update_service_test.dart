import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:economy/core/config/app_config.dart';
import 'package:economy/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// سرورِ ساختگی: هر درخواست را ثبت می‌کند و پاسخِ [handler] را می‌دهد.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions) handler;
  final urls = <String>[];
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    urls.add(options.uri.replace(queryParameters: {}).toString().replaceAll('?', ''));
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _bytes(List<int> data, [int status = 200]) => ResponseBody.fromBytes(
      data,
      status,
      headers: {
        Headers.contentLengthHeader: ['${data.length}'],
      },
    );

/// سرِ فایلِ zip/APK («PK\x03\x04») و چند بایت.
final _apk = [0x50, 0x4B, 0x03, 0x04, ...List.filled(5000, 7)];

void main() {
  AppUpdateInfo info(String name, {String url = 'http://s/updates/app.apk'}) =>
      AppUpdateInfo(versionCode: 0, versionName: name, notes: '', url: url);

  test('نسخه‌ی جدیدتر (بر اساسِ نامِ نسخه) → به‌روزرسانی موجود', () {
    expect(isUpdateAvailable('1.0.9', info('1.0.10')), isTrue);
    expect(isUpdateAvailable('1.0.10', info('1.0.10')), isFalse);
    expect(isUpdateAvailable('1.0.11', info('1.0.10')), isFalse);
    expect(isUpdateAvailable('1.0.9', null), isFalse);
    expect(isUpdateAvailable('1.0.9', info('1.0.10', url: '')), isFalse); // بدون فایل
  });

  test('مقایسه‌ی نامِ نسخه درست است (1.0.10 > 1.0.9)', () {
    expect(compareVersionNames('1.0.10', '1.0.9') > 0, isTrue);
    expect(compareVersionNames('1.0.9', '1.0.10') > 0, isFalse);
    expect(compareVersionNames('1.0.9', '1.0.9'), 0);
    expect(compareVersionNames('1.1.0', '1.0.99') > 0, isTrue);
    expect(compareVersionNames('2.0.0', '1.9.9') > 0, isTrue);
  });

  test('آدرس نسبی با ریشه کامل می‌شود؛ آدرس مطلق دست‌نخورده', () {
    final rel = AppUpdateInfo.fromJson(
        {'versionCode': 2, 'url': 'economy-latest.apk'}, base: 'http://s/updates');
    expect(rel.url, 'http://s/updates/economy-latest.apk');
    final abs = AppUpdateInfo.fromJson(
        {'versionCode': 2, 'url': 'http://x/y.apk'}, base: 'http://s/updates');
    expect(abs.url, 'http://x/y.apk');
  });

  test('updatesBaseUrl از apiBaseUrl، بخش /api/v1 را حذف می‌کند', () {
    expect(AppConfig.updatesBaseUrl, isNot(contains('/api/v1')));
    expect(AppConfig.updatesBaseUrl, endsWith('/updates'));
  });

  group('دانلودِ APK (Dio در پوشه‌ی خودِ برنامه، نه flutter_downloader)', () {
    late Directory dir;
    late _FakeAdapter adapter;
    late List<String> opened;
    const base = 'http://87.248.150.95/updates';
    const update = AppUpdateInfo(
        versionCode: 3021,
        versionName: '1.0.20',
        notes: '',
        url: 'http://koalaverifyshop.ir/updates/economy-latest.apk');

    UpdateService service(ResponseBody Function(RequestOptions) handler) {
      adapter = _FakeAdapter(handler);
      return UpdateService(base,
          dio: Dio()..httpClientAdapter = adapter,
          downloadDir: () async => dir,
          openInstaller: (path) async => opened.add(path));
    }

    setUp(() {
      dir = Directory.systemTemp.createTempSync('economy-update-test');
      opened = [];
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('دانلود، پیشرفت، پاک شدنِ نسخه‌ی قبل و باز شدنِ نصب‌کننده', () async {
      File('${dir.path}/economy-1.0.18.apk').writeAsStringSync('old');
      File('${dir.path}/other.txt').writeAsStringSync('keep');
      final s = service((_) => _bytes(_apk));
      final progress = <double>[];
      await s.downloadAndInstall(update, onProgress: progress.add);

      final path = '${dir.path}/economy-1.0.20.apk';
      expect(opened, [path]);
      expect(File(path).lengthSync(), _apk.length);
      expect(progress.last, 1.0);
      expect(File('${dir.path}/economy-1.0.18.apk').existsSync(), isFalse);
      expect(File('${dir.path}/other.txt').existsSync(), isTrue);
      expect(File('$path.part').existsSync(), isFalse);
      expect(adapter.urls, ['http://koalaverifyshop.ir/updates/economy-latest.apk']);
    });

    test('دامنه در دسترس نیست → همان فایل از سرورِ version.json', () async {
      final s = service((o) {
        if (o.uri.host == 'koalaverifyshop.ir') {
          throw DioException.connectionError(requestOptions: o, reason: 'dns');
        }
        return _bytes(_apk);
      });
      final path = await s.downloadApk(update);
      expect(File(path).existsSync(), isTrue);
      expect(adapter.urls, [
        'http://koalaverifyshop.ir/updates/economy-latest.apk',
        '$base/economy-latest.apk',
      ]);
    });

    test('صفحه‌ی HTML (خطا/فیلتر) به‌جای APK → خطای روشن، نه نصبِ فایلِ خراب', () async {
      final s = service((_) => _bytes('<html>blocked</html>'.codeUnits));
      await expectLater(
          s.downloadAndInstall(update),
          throwsA(isA<UpdateError>()
              .having((e) => e.message, 'message', contains('فایلِ برنامه نبود'))));
      expect(opened, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    test('کدِ ۴۰۴ از هر دو آدرس → پیام با کدِ خطا', () async {
      final s = service((_) => _bytes('nope'.codeUnits, 404));
      await expectLater(
          s.downloadApk(update),
          throwsA(isA<UpdateError>().having((e) => e.message, 'message', contains('404'))));
    });

    test('لغو: خطای لغو بالا می‌رود (پیامِ خطا نشان داده نمی‌شود)', () async {
      final s = service((_) => _bytes(_apk));
      final cancel = CancelToken()..cancel();
      await expectLater(
          s.downloadApk(update, cancelToken: cancel),
          throwsA(isA<DioException>().having(CancelToken.isCancel, 'isCancel', isTrue)));
    });

    test('لینکِ هم‌میزبان با سرور فقط یک بار امتحان می‌شود', () {
      final s = service((_) => _bytes(_apk));
      expect(
          s.downloadUrls(const AppUpdateInfo(
              versionCode: 1, versionName: '1', notes: '', url: '$base/economy-latest.apk')),
          ['$base/economy-latest.apk']);
    });

    test('describeUpdateError پیامِ فارسیِ قابلِ فهم می‌دهد', () {
      final o = RequestOptions(path: '/');
      expect(describeUpdateError(DioException.connectionError(requestOptions: o, reason: 'x')),
          contains('وصل نشد'));
      expect(describeUpdateError(DioException.receiveTimeout(timeout: Duration.zero, requestOptions: o)),
          contains('کند'));
      expect(describeUpdateError(const FileSystemException('x', 'p', OSError('No space left'))),
          contains('No space left'));
    });
  });
}
