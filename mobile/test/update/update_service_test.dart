import 'package:economy/core/config/app_config.dart';
import 'package:economy/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppUpdateInfo info(int code, {String url = 'http://s/updates/app.apk'}) =>
      AppUpdateInfo(versionCode: code, versionName: 'x', notes: '', url: url);

  test('نسخه‌ی جدیدتر → به‌روزرسانی موجود', () {
    expect(isUpdateAvailable(1, info(2)), isTrue);
    expect(isUpdateAvailable(2, info(2)), isFalse);
    expect(isUpdateAvailable(3, info(2)), isFalse);
    expect(isUpdateAvailable(1, null), isFalse);
    expect(isUpdateAvailable(1, info(2, url: '')), isFalse); // بدون فایل
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
}
