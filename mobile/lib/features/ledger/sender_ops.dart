/// «بانک‌ها» روی همان جدولِ فرستنده‌های مجاز (`allowed_senders`) — بدونِ داشبوردِ نسخه‌ی ۱.
library;

import 'dart:convert';

import '../../core/sms/raw_sms.dart';
import '../../core/store/app_store.dart';
import '../senders/data/sender_candidates.dart';
import 'ledger_controller.dart';

SenderOps ledgerSenderOps(
  AppStore repo, {
  required Future<List<RawSms>> Function() readInbox,
  required Future<({String? meName, String? meUserId})> Function() me,
}) {
  Future<Set<String>> dismissed() async {
    final raw = await repo.getSetting(SettingKeys.dismissedSenders);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  return SenderOps(
    candidates: () async {
      var inbox = const <RawSms>[];
      try {
        inbox = await readInbox();
      } catch (_) {
        // بی‌مجوزِ پیامک پیشنهادی نیست.
      }
      return findSenderCandidates(
        inbox: inbox,
        allowed: await repo.allowedSenders(),
        dismissed: await dismissed(),
      );
    },
    allow: (address, bankId) async {
      final who = await me();
      await repo.addAllowedSender(address,
          bankId: bankId, ownerName: who.meName, ownerUserId: who.meUserId);
    },
    dismiss: (address) async {
      final keys = await dismissed()
        ..add(address.trim());
      await repo.setSetting(SettingKeys.dismissedSenders, jsonEncode(keys.toList()));
    },
    remove: repo.deleteAllowedSender,
  );
}
