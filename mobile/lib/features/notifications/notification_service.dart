/// نوتیفیکیشن تراکنش جدید — با لمس، صفحه‌ی دسته‌بندی باز می‌شود.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/format/money_format.dart';

const _channelId = 'transactions';
const _channelName = 'تراکنش‌ها';
const _channelDesc = 'اعلان تراکنش‌های جدید برای دسته‌بندی';

const _androidDetails = AndroidNotificationDetails(
  _channelId,
  _channelName,
  channelDescription: _channelDesc,
  importance: Importance.high,
  priority: Priority.high,
);

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// [onTap] با شناسه‌ی تراکنش (payload) صدا زده می‌شود.
  static Future<void> init({void Function(String txId)? onTap}) async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (resp) {
        final id = resp.payload;
        if (id != null && id.isNotEmpty) onTap?.call(id);
      },
    );
    final android13 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(_channelId, _channelName,
          description: _channelDesc, importance: Importance.high),
    );
    await android13?.requestNotificationsPermission();
    _inited = true;
  }

  /// اگر اپ از طریق نوتیفیکیشن باز شده باشد، شناسه‌ی تراکنش را برمی‌گرداند.
  static Future<String?> launchPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details?.notificationResponse?.payload;
    }
    return null;
  }

  static Future<void> showTransaction(String txId, int amountRial) async {
    await _plugin.show(
      txId.hashCode & 0x7fffffff,
      'تراکنش جدید',
      '${formatToman(amountRial)} — برای دسته‌بندی لمس کنید',
      const NotificationDetails(android: _androidDetails),
      payload: txId,
    );
  }

  /// نسخه‌ی پس‌زمینه: پلاگین در ایزوله‌ی جدید از نو مقداردهی می‌شود.
  static Future<void> showFromBackground(String txId, int amountRial) async {
    final plugin = FlutterLocalNotificationsPlugin();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: android));
    final android13 = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(_channelId, _channelName,
          description: _channelDesc, importance: Importance.high),
    );
    await plugin.show(
      txId.hashCode & 0x7fffffff,
      'تراکنش جدید',
      '${formatToman(amountRial)} — برای دسته‌بندی لمس کنید',
      const NotificationDetails(android: _androidDetails),
      payload: txId,
    );
  }
}
