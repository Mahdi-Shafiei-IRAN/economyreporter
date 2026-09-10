import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payload همگام‌سازی متن خام پیامک را شامل نمی‌شود', () {
    final now = DateTime.utc(2026, 1, 1);
    final record = TransactionRecord(
      id: '1',
      kind: 'expense',
      amountRial: 1000,
      counterparty: 'فروشگاه',
      sourceMessageHash: 'h',
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
    };
    expect(payload.keys.toSet(), allowed);

    // صراحتاً: نه متن خام، نه فرستنده‌ی خام
    expect(payload.containsKey('rawBody'), isFalse);
    expect(payload.containsKey('rawSender'), isFalse);
    expect(payload.containsKey('body'), isFalse);
  });
}
