import 'package:economy/core/config/app_config.dart';
import 'package:economy/core/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
