/// نوتیفیکیشن‌ها: تراکنشِ نسخه‌ی ۱ (لمس = دسته‌بندی) و پیامکِ منتظرِ نسخه‌ی ۲ با دکمه‌های
/// «ثبت» / «تراکنش نیست» (لمس = صفحه‌ی منتظرِ تأیید).
library;

import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/database/app_database.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/models.dart';
import '../ledger/ledger_notifications.dart';

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

const _android = AndroidInitializationSettings('@mipmap/ic_launcher');

/// دکمه‌ی نوتیفیکیشن وقتی اپ بسته/پس‌زمینه است (ایزوله‌ی جدا؛ باید top-level باشد).
@pragma('vm:entry-point')
Future<void> ledgerNotificationBackground(NotificationResponse response) async {
  final key = ledgerKeyOf(response.payload);
  if (key == null) return;
  DartPluginRegistrant.ensureInitialized();
  final db = await openAppDatabase(singleInstance: false);
  try {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['device_id']);
    final deviceId = rows.isEmpty ? 'unknown' : rows.first['value'] as String? ?? 'unknown';
    await applyLedgerAction(LedgerRepository(db, deviceId: deviceId), response.actionId, key);
  } finally {
    await db.close();
  }
}

Future<AndroidFlutterLocalNotificationsPlugin?> _initPlugin(
    FlutterLocalNotificationsPlugin plugin,
    {DidReceiveNotificationResponseCallback? onResponse}) async {
  await plugin.initialize(
    const InitializationSettings(android: _android),
    onDidReceiveNotificationResponse: onResponse,
    onDidReceiveBackgroundNotificationResponse: ledgerNotificationBackground,
  );
  final android = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(
    const AndroidNotificationChannel(_channelId, _channelName,
        description: _channelDesc, importance: Importance.high),
  );
  return android;
}

Future<void> _showLedger(
    FlutterLocalNotificationsPlugin plugin, SmsItem item, LedgerAccount? account) {
  final (title, body) = ledgerNotificationText(item, account);
  return plugin.show(
    item.key.hashCode & 0x7fffffff,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        actions: [
          if (item.suggestion.isComplete)
            const AndroidNotificationAction(kLedgerActionAccept, 'ثبت'),
          const AndroidNotificationAction(kLedgerActionReject, 'تراکنش نیست'),
        ],
      ),
    ),
    payload: ledgerPayload(item.key),
  );
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// [onTap]: لمسِ خودِ نوتیفیکیشن با payload (شناسه‌ی تراکنشِ نسخه‌ی ۱ یا `ledger:<کلید>`).
  /// [onAction]: دکمه‌ی نوتیفیکیشن وقتی اپ باز است.
  static Future<void> init({
    void Function(String payload)? onTap,
    void Function(String actionId, String payload)? onAction,
  }) async {
    if (_inited) return;
    final android = await _initPlugin(_plugin, onResponse: (resp) {
      final payload = resp.payload ?? '';
      final action = resp.actionId;
      if (action != null && action.isNotEmpty) {
        onAction?.call(action, payload);
      } else if (payload.isNotEmpty) {
        onTap?.call(payload);
      }
    });
    await android?.requestNotificationsPermission();
    _inited = true;
  }

  /// اگر اپ از طریق نوتیفیکیشن باز شده باشد، payload را برمی‌گرداند.
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
    await _initPlugin(plugin);
    await plugin.show(
      txId.hashCode & 0x7fffffff,
      'تراکنش جدید',
      '${formatToman(amountRial)} — برای دسته‌بندی لمس کنید',
      const NotificationDetails(android: _androidDetails),
      payload: txId,
    );
  }

  static Future<void> showLedgerSms(SmsItem item, LedgerAccount? account) =>
      _showLedger(_plugin, item, account);

  static Future<void> showLedgerFromBackground(SmsItem item, LedgerAccount? account) async {
    final plugin = FlutterLocalNotificationsPlugin();
    await _initPlugin(plugin);
    await _showLedger(plugin, item, account);
  }
}
