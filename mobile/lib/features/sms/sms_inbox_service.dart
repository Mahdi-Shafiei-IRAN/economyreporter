/// خواندنِ پیامک از سیستم‌عامل: صندوقِ ورودی و دریافتِ زنده (اپ باز، پس‌زمینه یا بسته؛ گیرنده در
/// AndroidManifest). هر پیامکِ فرستنده‌ی مجاز فقط «منتظرِ تأیید» می‌شود و نوتیفیکیشنِ دکمه‌دار می‌آید؛
/// هیچ پیامکی خودش ثبت نمی‌شود (docs/v2-design.md).
library;

import 'package:another_telephony/telephony.dart';

import '../../core/database/app_database.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/sms_intake.dart';
import '../../core/sms/raw_sms.dart';
import '../ledger/ledger_notifications.dart';
import '../notifications/notification_service.dart';
import '../transactions/data/transaction_repository.dart';

IncomingSms toIncomingSms(RawSms raw) => IncomingSms(
    sender: raw.sender, body: raw.body, receivedAt: (raw.receivedAt ?? DateTime.now()).toUtc());

class SmsInboxService {
  final Telephony _telephony = Telephony.instance;

  /// هر پیامکِ زنده (اپ باز).
  final Future<void> Function(RawSms)? onLiveSms;

  SmsInboxService({this.onLiveSms});

  /// درخواست مجوز خواندن/دریافت پیامک.
  Future<bool> requestPermission() async {
    final granted = await _telephony.requestSmsPermissions;
    return granted ?? false;
  }

  /// پیامک‌های صندوق ورودی (جدیدترین اول)؛ [limit] = null یعنی همه. چیزی ذخیره نمی‌کند.
  Future<List<RawSms>> readInbox({int? limit}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return (limit == null ? messages : messages.take(limit)).map(_toRaw).toList();
  }

  /// گوش‌دادن زنده به پیامک‌های ورودی.
  void startListener() {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async => onLiveSms?.call(_toRaw(message)),
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
  }
}

RawSms _toRaw(SmsMessage m) => RawSms(
      sender: m.address ?? '',
      body: m.body ?? '',
      receivedAt: m.date != null ? DateTime.fromMillisecondsSinceEpoch(m.date!) : DateTime.now(),
    );

/// هندلر پس‌زمینه (ایزوله‌ی جدا). باید top-level و vm:entry-point باشد. دیتابیس را با اتصالِ جدا باز
/// می‌کند (تا بستنش اتصالِ اپ را نبندد)؛ پیامکِ منتظر + نوتیفیکیشنِ «ثبت» / «تراکنش نیست».
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final db = await openAppDatabase(singleInstance: false);
  try {
    final repo = TransactionRepository(db);
    final ledger = LedgerRepository(db,
        deviceId: await repo.getSetting(SettingKeys.deviceId) ?? 'unknown');
    await ledgerIntakeAndNotify(ledger, toIncomingSms(_toRaw(message)),
        allowed: await repo.allowedSenders(),
        notify: NotificationService.showLedgerFromBackground);
  } finally {
    await db.close();
  }
}
