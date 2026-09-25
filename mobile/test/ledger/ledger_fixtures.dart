import 'package:economy/core/ledger/models.dart';

Entry entry(String id, EntryKind kind, int amount, DateTime at,
        {int? bal, String acc = 'a1', DateTime? created}) =>
    Entry(
      id: id,
      accountId: acc,
      kind: kind,
      amountRial: amount,
      occurredAt: at,
      bankBalanceAfter: bal,
      source: bal == null ? EntrySource.manual : EntrySource.sms,
      createdAt: created ?? at,
      updatedAt: created ?? at,
    );

Checkpoint checkpoint(String id, int balance, DateTime at, {String acc = 'a1'}) => Checkpoint(
      id: id,
      accountId: acc,
      at: at,
      balanceRial: balance,
      createdAt: at,
      updatedAt: at,
    );

SmsItem smsItem(String key,
        {required DateTime at,
        EntryKind? kind,
        int? amount,
        String? accountId,
        SmsStatus status = SmsStatus.pending}) =>
    SmsItem(
      key: key,
      contentHash: key,
      sender: 'bank',
      receivedAt: at,
      suggestion: SmsSuggestion(kind: kind, amountRial: amount, occurredAt: at, accountId: accountId),
      status: status,
      parserVersion: 4,
    );
