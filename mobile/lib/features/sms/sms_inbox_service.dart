/// سرویس خواندن پیامک از سیستم‌عامل (بخش دستگاهی).
///
/// دو مسیر: (۱) وارد کردن صندوق پیام هنگام باز شدن اپ، (۲) گوش‌دادن زنده به
/// پیامک‌های ورودی (پیش‌زمینه و پس‌زمینه). پارس/ذخیره در SmsImporter (تست‌شده).
library;

import 'package:another_telephony/telephony.dart';

import '../../core/database/app_database.dart';
import '../../core/sms/sms_importer.dart';
import '../notifications/notification_service.dart';
import '../transactions/data/transaction_repository.dart';

class SmsInboxService {
  final Telephony _telephony = Telephony.instance;
  final SmsImporter importer;

  /// وقتی تراکنش جدیدی وارد شد صدا زده می‌شود (برای تازه‌سازی داشبورد).
  final void Function()? onChanged;

  /// وقتی یک تراکنشِ جدید (زنده) گرفته شد — برای نوتیفیکیشن.
  final void Function(ImportedTx)? onTransactionCaptured;

  SmsInboxService({
    required this.importer,
    this.onChanged,
    this.onTransactionCaptured,
  });

  /// درخواست مجوز خواندن/دریافت پیامک.
  Future<bool> requestPermission() async {
    final granted = await _telephony.requestSmsPermissions;
    return granted ?? false;
  }

  /// وارد کردن پیامک‌های اخیر صندوق ورودی (هنگام باز شدن اپ). تعداد تراکنش جدید.
  Future<int> importInbox({int limit = 300}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    final raws = messages.take(limit).map(_toRaw).toList();
    final result = await importer.importAll(raws);
    if (result.created > 0) onChanged?.call();
    return result.created;
  }

  /// گوش‌دادن زنده به پیامک‌های ورودی.
  void startListener() {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final imported = await importer.importOne(_toRaw(message));
        if (imported != null) {
          onChanged?.call();
          onTransactionCaptured?.call(imported);
        }
      },
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
  }

  RawSms _toRaw(SmsMessage m) => RawSms(
        sender: m.address ?? '',
        body: m.body ?? '',
        receivedAt: m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now(),
      );
}

/// هندلر پس‌زمینه (ایزوله‌ی جدا). باید top-level و vm:entry-point باشد.
/// در پس‌زمینه DB خودش را باز می‌کند و تراکنش را ذخیره می‌کند.
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final db = await openAppDatabase();
  try {
    final importer = SmsImporter(TransactionRepository(db));
    final imported = await importer.importOne(RawSms(
      sender: message.address ?? '',
      body: message.body ?? '',
      receivedAt: DateTime.now(),
    ));
    if (imported != null) {
      await NotificationService.showFromBackground(
          imported.id, imported.amountRial);
    }
  } finally {
    await db.close();
  }
}
