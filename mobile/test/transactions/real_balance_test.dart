import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord tx({
  required String id,
  required String kind,
  int? amount,
  int? balanceAfter,
  String card = '1111',
  String bank = 'mellat',
  DateTime? at,
}) {
  final t = at ?? DateTime.utc(2026, 9, 10, 8);
  return TransactionRecord(
    id: id,
    kind: kind,
    amountRial: amount,
    balanceAfterRial: balanceAfter,
    cardLast4: card,
    bankId: bank,
    transactionDate: t,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  test('موجودی = مانده‌ی آخرین پیامک (شاملِ موجودیِ ابتدای دوره)', () {
    // خالص این ماه = +۲م − ۱م = ۱م، ولی مانده‌ی واقعی ۱۵م است.
    final balance = realBalanceRial([
      tx(id: 'a', kind: 'income', amount: 2000000, balanceAfter: 15000000,
          at: DateTime.utc(2026, 9, 5)),
      tx(id: 'b', kind: 'expense', amount: 1000000, balanceAfter: 14000000,
          at: DateTime.utc(2026, 9, 10)),
    ]);
    // آخرین مانده ۱۴م است (بعد از خرجِ ۱م)
    expect(balance, 14000000);
  });

  test('اگر پیامکِ جدیدتر مانده نداشت، از آخرین مانده جلو می‌آید', () {
    final balance = realBalanceRial([
      tx(id: 'a', kind: 'income', amount: 5000000, balanceAfter: 10000000,
          at: DateTime.utc(2026, 9, 5)),
      tx(id: 'b', kind: 'expense', amount: 2000000, balanceAfter: null,
          at: DateTime.utc(2026, 9, 10)),
    ]);
    expect(balance, 8000000); // ۱۰م − ۲م
  });

  test('چند کارت: موجودی‌ها جمع می‌شوند', () {
    final balance = realBalanceRial([
      tx(id: 'a', kind: 'income', amount: 0, balanceAfter: 15000000, card: '1111'),
      tx(id: 'b', kind: 'income', amount: 0, balanceAfter: 3000000, card: '2222'),
    ]);
    expect(balance, 18000000);
  });

  test('asOf: فقط تا پایان دوره حساب می‌شود', () {
    final balance = realBalanceRial([
      tx(id: 'a', kind: 'income', amount: 1000000, balanceAfter: 5000000,
          at: DateTime.utc(2026, 9, 10)),
      tx(id: 'b', kind: 'income', amount: 1000000, balanceAfter: 6000000,
          at: DateTime.utc(2026, 10, 2)),
    ], asOf: DateTime.utc(2026, 9, 30));
    expect(balance, 5000000); // تراکنشِ مهر حساب نمی‌شود
  });
}
