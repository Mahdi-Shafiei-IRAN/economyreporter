import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payload همگام‌سازی متن خام پیامک و شماره‌ی حساب را شامل نمی‌شود', () {
    final now = DateTime.utc(2026, 1, 1);
    final record = TransactionRecord(
      id: '1',
      kind: 'expense',
      amountRial: 1000,
      counterparty: 'فروشگاه',
      sourceMessageHash: 'h',
      accountRef: '1000000001',
      cardLast4: '1234',
      smsSender: 'BankMellat',
      smsBody: 'خرید مبلغ 1,000 ریال از کارت 1234',
      createdAt: now,
      updatedAt: now,
      clientCreatedAt: now,
    );

    final payload = record.toSyncPayload();

    // فقط همین کلیدهای ساختاریافته مجازند؛ هیچ متن خام پیامکی نباید برود.
    const allowed = {
      'id',
      'kind',
      'amount_rial',
      'balance_after_rial',
      'raw_amount',
      'raw_unit',
      'counterparty',
      'description',
      'source',
      'source_message_hash',
      'device_id',
      'needs_review',
      'transaction_date',
      'client_created_at',
      'client_updated_at',
      'bank_id',
      'card_last4',
      'owner_member',
      'person_name',
      'wallet_label',
      'allocations',
      'is_deleted',
    };
    expect(payload.keys.toSet(), allowed);

    // صراحتاً: نه متن خام، نه فرستنده‌ی خام، نه شماره‌ی حساب
    final values = payload.values.map((v) => '$v').join('|');
    expect(values.contains('خرید مبلغ'), isFalse);
    expect(values.contains('BankMellat'), isFalse);
    expect(values.contains('1000000001'), isFalse);
    expect(payload['card_last4'], '1234'); // فقط ۴ رقم آخر
  });

  test('فیلدهای متنی payload هرگز null نیستند (سرور null را رد می‌کرد)', () {
    final now = DateTime.utc(2026, 1, 1);
    final payload = TransactionRecord(
      id: '1',
      kind: 'income',
      amountRial: 5000,
      createdAt: now,
      updatedAt: now,
    ).toSyncPayload();
    for (final key in [
      'raw_amount',
      'counterparty',
      'description',
      'source_message_hash',
      'device_id',
      'bank_id',
      'card_last4',
      'person_name',
      'wallet_label',
    ]) {
      expect(payload[key], isA<String>(), reason: key);
    }
  });
}
