/// نوتیفیکیشنِ پیامکِ تازه با دکمه‌های «ثبت» و «تراکنش نیست» (طرح ۷.۳): منطق، بدونِ پلاگین
/// (نمایش در NotificationService).
library;

import '../../core/format/money_format.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/models.dart';
import '../../core/ledger/sms_intake.dart';
import '../senders/data/allowed_sender.dart';
import 'ledger_text.dart';

const kLedgerPayloadPrefix = 'ledger:';
const kLedgerActionAccept = 'ledger_accept';
const kLedgerActionReject = 'ledger_reject';

String ledgerPayload(String smsKey) => '$kLedgerPayloadPrefix$smsKey';

String? ledgerKeyOf(String? payload) =>
    (payload != null && payload.startsWith(kLedgerPayloadPrefix))
        ? payload.substring(kLedgerPayloadPrefix.length)
        : null;

/// (عنوان، متن). متنِ خامِ پیامک در نوتیفیکیشن نمی‌آید (روی صفحه‌ی قفل دیده می‌شود).
(String, String) ledgerNotificationText(SmsItem item, LedgerAccount? account) {
  final g = item.suggestion;
  final who = account == null ? 'پیامکِ بانک' : accountTitle(account);
  final amount = g.amountRial == null ? '' : ' ${formatToman(g.amountRial!)}';
  final notTx = notTxText(g.notTxReason);
  return (
    '$who: ${kindLabel(g.kind)}$amount',
    [
      notTx ?? 'منتظرِ تأیید',
      if (g.balanceRial != null) 'مانده ${formatToman(g.balanceRial!)}',
      if (g.likelyDuplicate) 'احتمالاً تکراری',
    ].join(' • '),
  );
}

/// دکمه‌ی نوتیفیکیشن. فقط پیامکِ هنوز منتظر؛ «ثبت» فقط با پیشنهادِ کامل. true = انجام شد.
Future<bool> applyLedgerAction(LedgerRepository repo, String? actionId, String smsKey) async {
  final item = await repo.smsItem(smsKey);
  if (item == null || item.status != SmsStatus.pending) return false;
  switch (actionId) {
    case kLedgerActionAccept when item.suggestion.isComplete:
      await repo.acceptSuggested(smsKey);
      return true;
    case kLedgerActionReject:
      await repo.rejectSms(smsKey, RejectReason.notTx);
      return true;
  }
  return false;
}

/// پیامکِ زنده/پس‌زمینه → پیامکِ منتظر → نوتیفیکیشن (فقط برای پیامکِ تازه‌ی منتظر).
Future<List<SmsItem>> ledgerIntakeAndNotify(
  LedgerRepository repo,
  IncomingSms sms, {
  required List<AllowedSender> allowed,
  required Future<void> Function(SmsItem item, LedgerAccount? account) notify,
}) async {
  final results = await repo.intakeAll([sms], allowed: allowed);
  final fresh = [
    for (final r in results)
      if (r is IntakeNew && r.item.status == SmsStatus.pending) r.item,
  ];
  if (fresh.isEmpty) return fresh;
  final accounts = {for (final a in await repo.accounts()) a.id: a};
  for (final item in fresh) {
    await notify(item, accounts[item.suggestion.accountId]);
  }
  return fresh;
}
