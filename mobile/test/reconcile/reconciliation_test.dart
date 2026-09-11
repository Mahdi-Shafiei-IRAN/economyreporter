import 'package:economy/core/reconcile/reconciliation.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _tx({
  required String id,
  required String card,
  required String kind,
  required int amount,
  required int balance,
  required int minute,
}) {
  final at = DateTime.utc(2026, 1, 1, 12, minute);
  return TransactionRecord(
    id: id,
    cardLast4: card,
    kind: kind,
    amountRial: amount,
    balanceAfterRial: balance,
    transactionDate: at,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  const service = ReconciliationService();

  test('زنجیره‌ی هماهنگ → هیچ گپی', () {
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      _tx(id: 'b', card: '1234', kind: 'expense', amount: 300000, balance: 700000, minute: 1),
      _tx(id: 'c', card: '1234', kind: 'expense', amount: 200000, balance: 500000, minute: 2),
    ];
    expect(service.findGaps(txs), isEmpty);
  });

  test('برداشتِ جاافتاده کشف می‌شود', () {
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      // انتظار مانده 800000 ولی واقعی 500000 → یک برداشت 300000 جا افتاده
      _tx(id: 'b', card: '1234', kind: 'expense', amount: 200000, balance: 500000, minute: 1),
    ];
    final gaps = service.findGaps(txs);
    expect(gaps, hasLength(1));
    expect(gaps.first.expectedBalanceRial, 800000);
    expect(gaps.first.actualBalanceRial, 500000);
    expect(gaps.first.missingAmountRial, -300000);
    expect(gaps.first.cardLast4, '1234');
  });

  test('واریزِ جاافتاده کشف می‌شود', () {
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      _tx(id: 'b', card: '1234', kind: 'income', amount: 500000, balance: 2000000, minute: 1),
    ];
    final gaps = service.findGaps(txs);
    expect(gaps, hasLength(1));
    expect(gaps.first.missingAmountRial, 500000); // 2000000 - 1500000
  });

  test('transfer نادیده گرفته می‌شود (قابل بررسی نیست)', () {
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      _tx(id: 'b', card: '1234', kind: 'transfer', amount: 100000, balance: 5000000, minute: 1),
    ];
    expect(service.findGaps(txs), isEmpty);
  });

  test('کارت‌های متفاوت مستقل بررسی می‌شوند', () {
    final txs = [
      _tx(id: 'a', card: '1111', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      _tx(id: 'b', card: '2222', kind: 'expense', amount: 50000, balance: 200000, minute: 1),
    ];
    // هر کارت فقط یک رکورد دارد → هیچ زوجی برای مقایسه نیست
    expect(service.findGaps(txs), isEmpty);
  });

  test('تطبیق مانده‌ی حساب‌محور (بدون کارت) هم کار می‌کند', () {
    TransactionRecord acc({
      required String id,
      required String account,
      required String kind,
      required int amount,
      required int balance,
      required int minute,
    }) {
      final at = DateTime.utc(2026, 1, 1, 12, minute);
      return TransactionRecord(
        id: id,
        accountRef: account,
        kind: kind,
        amountRial: amount,
        balanceAfterRial: balance,
        transactionDate: at,
        createdAt: at,
        updatedAt: at,
      );
    }

    final txs = [
      acc(id: 'a', account: '0279049244816', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      // انتظار 800000 ولی واقعی 500000 → برداشت 300000 جاافتاده
      acc(id: 'b', account: '0279049244816', kind: 'expense', amount: 200000, balance: 500000, minute: 1),
    ];
    final gaps = service.findGaps(txs);
    expect(gaps, hasLength(1));
    expect(gaps.first.accountRef, '0279049244816');
    expect(gaps.first.cardLast4, isNull);
    expect(gaps.first.missingAmountRial, -300000);
  });

  test('رکورد بدون مانده یا کارت نادیده گرفته می‌شود', () {
    final noBalance = TransactionRecord(
      id: 'x',
      cardLast4: '1234',
      kind: 'expense',
      amountRial: 100000,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(service.findGaps([noBalance]), isEmpty);
  });

  test('ثبت دستیِ بدون مانده (بین دو پیامک) شکاف را پر می‌کند', () {
    final manual = TransactionRecord(
      id: 'm',
      cardLast4: '1234',
      kind: 'expense',
      amountRial: 300000,
      source: 'manual',
      transactionDate: DateTime.utc(2026, 1, 1, 12, 0, 30),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      manual,
      _tx(id: 'b', card: '1234', kind: 'expense', amount: 200000, balance: 500000, minute: 1),
    ];
    expect(service.findGaps(txs), isEmpty);
  });

  test('شکافِ نادیده‌گرفته‌شده دوباره نشان داده نمی‌شود', () {
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      _tx(id: 'b', card: '1234', kind: 'expense', amount: 200000, balance: 500000, minute: 1),
    ];
    final gap = service.findGaps(txs).single;
    expect(gap.key, 'a|b');
    expect(service.findGaps(txs, dismissed: {gap.key}), isEmpty);
  });

  test('بدون زمان واقعی (فقط زمانِ واردشدن) مقایسه نمی‌شود — هشدار اشتباه نمی‌دهد', () {
    TransactionRecord imported(String id, int amount, int balance) => TransactionRecord(
          id: id,
          cardLast4: '1234',
          kind: 'expense',
          amountRial: amount,
          balanceAfterRial: balance,
          clientCreatedAt: DateTime.utc(2026, 9, 11),
          createdAt: DateTime.utc(2026, 9, 11),
          updatedAt: DateTime.utc(2026, 9, 11),
        );
    expect(service.findGaps([imported('a', 1, 1000), imported('b', 1, 5000)]), isEmpty);
  });

  test('تراکنش منتظر بازبینی زنجیره را از مانده‌ی خودش از نو شروع می‌کند', () {
    final failed = TransactionRecord(
      id: 'f',
      cardLast4: '1234',
      kind: 'expense',
      amountRial: 900000,
      balanceAfterRial: 1000000, // خرید ناموفق: مانده عوض نشده
      needsReview: true,
      transactionDate: DateTime.utc(2026, 1, 1, 12, 0, 30),
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    final txs = [
      _tx(id: 'a', card: '1234', kind: 'income', amount: 0, balance: 1000000, minute: 0),
      failed,
      _tx(id: 'b', card: '1234', kind: 'expense', amount: 200000, balance: 800000, minute: 1),
    ];
    expect(service.findGaps(txs), isEmpty);
  });
}
