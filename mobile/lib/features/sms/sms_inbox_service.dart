/// سرویس خواندن پیامک از سیستم‌عامل (بخش دستگاهی).
///
/// دو مسیر: (۱) دریافت زنده‌ی پیامک ورودی — به‌محض رسیدن در دیتابیس ذخیره
/// می‌شود (اپ باز، پس‌زمینه یا بسته؛ گیرنده در AndroidManifest)، پس پاک‌شدن
/// پیامک از صندوق اثری روی اپ ندارد. (۲) وارد کردن صندوق هنگام باز شدن اپ،
/// برای پیامک‌هایی که وقتی گوشی خاموش بود رسیده‌اند.
/// در هر دو مسیر فقط پیامکِ فرستنده‌های مجاز ثبت می‌شود (SmsImporter، تست‌شده).
library;

import 'package:another_telephony/telephony.dart';

import '../../core/database/app_database.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/sms_intake.dart';
import '../../core/sms/sms_importer.dart';
import '../ledger/ledger_notifications.dart';
import '../notifications/notification_service.dart';
import '../transactions/data/transaction_repository.dart';

IncomingSms toIncomingSms(RawSms raw) => IncomingSms(
    sender: raw.sender, body: raw.body, receivedAt: (raw.receivedAt ?? DateTime.now()).toUtc());

class SmsInboxService {
  final Telephony _telephony = Telephony.instance;
  final SmsImporter importer;

  /// وقتی تراکنش جدیدی وارد شد صدا زده می‌شود (برای تازه‌سازی داشبورد).
  final void Function()? onChanged;

  /// وقتی یک تراکنشِ جدید (زنده) گرفته شد — برای نوتیفیکیشن.
  final void Function(ImportedTx)? onTransactionCaptured;

  /// هر پیامکِ زنده (برای دفترِ نسخه‌ی ۲).
  final Future<void> Function(RawSms)? onLiveSms;

  SmsInboxService({
    required this.importer,
    this.onChanged,
    this.onTransactionCaptured,
    this.onLiveSms,
  });

  /// درخواست مجوز خواندن/دریافت پیامک.
  Future<bool> requestPermission() async {
    final granted = await _telephony.requestSmsPermissions;
    return granted ?? false;
  }

  /// پیامک‌های صندوق ورودی (جدیدترین اول)؛ [limit] = null یعنی همه. چیزی ذخیره نمی‌کند؛
  /// برای پیشنهاد فرستنده‌ها و عیب‌یابی هم استفاده می‌شود. (سیستم‌عامل به‌هرحال همه را
  /// برمی‌گرداند؛ محدودیت فقط پردازش را کم می‌کند.)
  Future<List<RawSms>> readInbox({int? limit}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return (limit == null ? messages : messages.take(limit)).map(_toRaw).toList();
  }

  /// وارد کردن پیامک‌های صندوق. [full]: همه‌ی صندوق (بعد از مجاز کردنِ فرستنده یا
  /// «خواندنِ دوباره»)؛ وگرنه فقط پیامک‌های بعد از آخرین خواندن (باز شدنِ اپ).
  /// قبلاً فقط ۳۰۰ پیامکِ آخرِ کلِ صندوق خوانده می‌شد و پیامکِ قدیمی‌ترِ بانک هیچ‌وقت
  /// ثبت نمی‌شد. تعداد تراکنش جدید را برمی‌گرداند.
  Future<int> importInbox({bool full = false}) async {
    final result = await importer.importInbox(await readInbox(), full: full);
    if (result.created > 0) onChanged?.call();
    return result.created;
  }

  /// گوش‌دادن زنده به پیامک‌های ورودی.
  void startListener() {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) async {
        final raw = _toRaw(message);
        final imported = await importer.importOne(raw);
        if (imported != null) {
          onChanged?.call();
          onTransactionCaptured?.call(imported);
        }
        await onLiveSms?.call(raw);
      },
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
  }
}

RawSms _toRaw(SmsMessage m) => RawSms(
      sender: m.address ?? '',
      body: m.body ?? '',
      receivedAt: m.date != null
          ? DateTime.fromMillisecondsSinceEpoch(m.date!)
          : DateTime.now(),
    );

/// هندلر پس‌زمینه (ایزوله‌ی جدا). باید top-level و vm:entry-point باشد.
/// در پس‌زمینه DB را با اتصال جداگانه باز می‌کند (تا بستنش اتصال اپ را نبندد)
/// و تراکنش را همان لحظه ذخیره می‌کند. با نسخه‌ی ۲ روشن: پیامکِ منتظر + نوتیفیکیشنِ دکمه‌دار
/// (و نوتیفیکیشنِ دسته‌بندیِ نسخه‌ی ۱ نه).
@pragma('vm:entry-point')
Future<void> backgroundSmsHandler(SmsMessage message) async {
  final db = await openAppDatabase(singleInstance: false);
  try {
    final repo = TransactionRepository(db);
    final raw = _toRaw(message);
    final imported = await SmsImporter(repo).importOne(raw);
    final ledger = LedgerRepository(db,
        deviceId: await repo.getSetting(SettingKeys.deviceId) ?? 'unknown');
    if (await ledger.isEnabled()) {
      await ledgerIntakeAndNotify(ledger, toIncomingSms(raw),
          allowed: await repo.allowedSenders(),
          notify: NotificationService.showLedgerFromBackground);
    } else if (imported != null && imported.promptCategorize) {
      await NotificationService.showFromBackground(
          imported.id, imported.amountRial);
    }
  } finally {
    await db.close();
  }
}
