import 'package:economy/core/diagnostics/balance_chain.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _tx(
  String id, {
  required String kind,
  int? amount,
  int? balance,
  required int minute,
  String? card,
  String? account = '1000000001',
  String? bank = 'mellat',
  bool review = false,
}) {
  final at = DateTime.utc(2026, 9, 1, 8, minute);
  return TransactionRecord(
    id: id,
    bankId: bank,
    kind: kind,
    amountRial: amount,
    balanceAfterRial: balance,
    cardLast4: card,
    accountRef: card == null ? account : null,
    needsReview: review,
    transactionDate: at,
    createdAt: at,
    updatedAt: at,
  );
}

List<ChainStatus> _statuses(BalanceChainReport r) =>
    [for (final l in r.accounts.single.links) l.status];

void main() {
  test('زنجیره‌ی سالم: همه جور', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 500, balance: 10000, minute: 0),
      _tx('b', kind: 'expense', amount: 3000, balance: 7000, minute: 1),
      _tx('c', kind: 'income', amount: 1000, balance: 8000, minute: 2),
    ]);
    expect(_statuses(r), [ChainStatus.start, ChainStatus.ok, ChainStatus.ok]);
    expect(r.problemCount, 0);
    expect(r.accounts.single.lastBalanceRial, 8000);
  });

  test('واریزی که برداشت ثبت شده → «نوع برعکس» با نوعِ پیشنهادی', () {
    // مثلاً «واریز … مانده قابل برداشت» که پارسر برداشت خوانده.
    final r = auditBalanceChains([
      _tx('a', kind: 'expense', amount: 100, balance: 10000, minute: 0),
      _tx('b', kind: 'expense', amount: 2000, balance: 12000, minute: 1),
    ]);
    final link = r.accounts.single.links[1];
    expect(link.status, ChainStatus.signFlipped);
    expect(link.suggestedKind, 'income');
    expect(link.bankDeltaRial, 2000);
    expect(link.diffRial, 4000); // دو برابرِ مبلغ
  });

  test('پیامکی که مانده را عوض نکرده → تکراری/غیرتراکنش', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'expense', amount: 500, balance: 9500, minute: 0),
      _tx('b', kind: 'expense', amount: 500, balance: 9500, minute: 1),
    ]);
    expect(_statuses(r), [ChainStatus.start, ChainStatus.noEffect]);
  });

  test('پیامکِ جاافتاده → ناجور با مقدارِ اختلاف', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 100, balance: 10000, minute: 0),
      _tx('b', kind: 'expense', amount: 1000, balance: 6000, minute: 1),
    ]);
    final link = r.accounts.single.links[1];
    expect(link.status, ChainStatus.mismatch);
    expect(link.expectedBalanceRial, 9000);
    expect(link.diffRial, -3000); // برداشتِ ۳۰۰۰ ثبت نشده
  });

  test('انتقال/بازبینی: نوع از روی مانده پیشنهاد می‌شود', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0),
      // کارت‌به‌کارتِ دریافتی از غریبه که «انتقال» ثبت شده
      _tx('b', kind: 'transfer', amount: 4000, balance: 14000, minute: 1),
      // نوع نامعلوم (بازبینی) که در واقع برداشت بوده
      _tx('c', kind: 'unknown', amount: 2000, balance: 12000, minute: 2, review: true),
    ]);
    final links = r.accounts.single.links;
    // انتقالی که مانده را به همان اندازه جابه‌جا کرده «جور» است.
    expect(links[1].status, ChainStatus.ok);
    expect(links[2].status, ChainStatus.kindSuggested);
    expect(links[2].suggestedKind, 'expense');
  });

  test('ترتیبِ زمانیِ جابه‌جا تشخیص داده می‌شود و بقیه را خراب نمی‌کند', () {
    // ترتیبِ واقعی: 10000 → (−1000) 9000 → (+500) 9500 → (−500) 9000
    // ولی زمانِ ثبت‌شده‌ی دو پیامکِ وسط جابه‌جاست.
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0),
      _tx('c', kind: 'income', amount: 500, balance: 9500, minute: 1),
      _tx('b', kind: 'expense', amount: 1000, balance: 9000, minute: 2),
      _tx('d', kind: 'expense', amount: 500, balance: 9000, minute: 3),
    ]);
    expect(_statuses(r), [
      ChainStatus.start,
      ChainStatus.outOfOrder,
      ChainStatus.outOfOrder,
      ChainStatus.ok,
    ]);
  });

  test('تراکنشِ بی‌مانده (ثبت دستی) به انتظارِ بعدی اضافه می‌شود', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0),
      _tx('m', kind: 'expense', amount: 3000, minute: 1),
      _tx('b', kind: 'expense', amount: 1000, balance: 6000, minute: 2),
    ]);
    expect(_statuses(r), [ChainStatus.start, ChainStatus.noBalance, ChainStatus.ok]);
  });

  test('حذف‌شده‌ها در زنجیره نیستند', () {
    final deleted = _tx('x', kind: 'expense', amount: 500, balance: 1, minute: 1)
        .copyWith(deletedAt: DateTime.utc(2026, 9, 2));
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0),
      deleted,
      _tx('b', kind: 'expense', amount: 1000, balance: 9000, minute: 2),
    ]);
    expect(_statuses(r), [ChainStatus.start, ChainStatus.ok]);
  });

  test('یک حساب که گاهی با کارت و گاهی با شماره حساب آمده → هشدارِ دوبار شمردن', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0), // حساب
      _tx('b', kind: 'expense', amount: 2000, balance: 8000, minute: 1, card: '1234'),
      _tx('c', kind: 'income', amount: 500, balance: 8500, minute: 2), // حساب
      _tx('d', kind: 'expense', amount: 100, balance: 8400, minute: 3, card: '1234'),
    ]);
    expect(r.accounts, hasLength(2));
    expect(r.splitHints, hasLength(1));
    expect(r.splitHints.single.switches, 3);
    expect(r.splitHints.single.consistent, 3);
  });

  test('دو حسابِ واقعاً جدا در یک بانک → هشدار نمی‌دهد', () {
    final r = auditBalanceChains([
      _tx('a', kind: 'income', amount: 1, balance: 10000, minute: 0),
      _tx('b', kind: 'expense', amount: 2000, balance: 50000, minute: 1, card: '1234'),
      _tx('c', kind: 'income', amount: 500, balance: 10500, minute: 2),
      _tx('d', kind: 'expense', amount: 100, balance: 49900, minute: 3, card: '1234'),
    ]);
    expect(r.splitHints, isEmpty);
  });
}
