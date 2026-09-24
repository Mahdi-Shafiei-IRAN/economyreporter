import 'package:economy/core/diagnostics/balance_breakdown.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// شهریور ۱۴۰۵ = 2026-08-23 تا 2026-09-22 (به وقت ایران).
const _shahrivar = Period.month(1405, 6);

TransactionRecord _tx(
  String id, {
  required String kind,
  required int amount,
  int? balance,
  required DateTime at,
  String? account = '1000000001',
  String? card,
  bool review = false,
}) =>
    TransactionRecord(
      id: id,
      bankId: 'mellat',
      kind: kind,
      amountRial: amount,
      balanceAfterRial: balance,
      accountRef: card == null ? account : null,
      cardLast4: card,
      needsReview: review,
      transactionDate: at,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  test('جمعِ جدول دقیقاً همان عددِ کارتِ خلاصه است و اختلاف صفر وقتی همه‌چیز جور است', () {
    final items = [
      _tx('o', kind: 'income', amount: 100, balance: 10000, at: DateTime.utc(2026, 8, 10)),
      _tx('a', kind: 'expense', amount: 3000, balance: 7000, at: DateTime.utc(2026, 9, 1)),
      _tx('b', kind: 'income', amount: 1000, balance: 8000, at: DateTime.utc(2026, 9, 5)),
    ];
    final b = computeBalanceBreakdown(items, _shahrivar);
    final start = _shahrivar.from!.subtract(const Duration(microseconds: 1));
    expect(b.openingRial, realBalanceRial(items, asOf: start));
    expect(b.openingRial, 10000);
    expect(b.incomeRial, 1000);
    expect(b.expenseRial, 3000);
    expect(b.expectedClosingRial, 8000);
    expect(b.bankClosingRial, 8000);
    expect(b.diffRial, 0);
    expect(b.cards.single.openingIsEstimate, isFalse);
  });

  test('واریزی که برداشت خوانده شده → اختلاف = دو برابرِ مبلغ', () {
    final items = [
      _tx('o', kind: 'income', amount: 100, balance: 10000, at: DateTime.utc(2026, 8, 10)),
      // در واقع واریز ۲۰۰۰ بوده (مانده بالا رفته)
      _tx('a', kind: 'expense', amount: 2000, balance: 12000, at: DateTime.utc(2026, 9, 1)),
    ];
    final b = computeBalanceBreakdown(items, _shahrivar);
    expect(b.expectedClosingRial, 8000);
    expect(b.bankClosingRial, 12000);
    expect(b.diffRial, 4000);
  });

  test('بدون مانده‌ی قبل از دوره، اول دوره «تخمینی» است', () {
    final items = [
      _tx('p', kind: 'expense', amount: 500, at: DateTime.utc(2026, 8, 10)), // بی‌مانده
      _tx('a', kind: 'expense', amount: 1000, balance: 20000, at: DateTime.utc(2026, 9, 1)),
    ];
    final b = computeBalanceBreakdown(items, _shahrivar);
    final card = b.cards.single;
    expect(card.openingIsEstimate, isTrue);
    expect(card.openingRial, -500); // فقط جمعِ علامت‌دار، نه موجودیِ واقعی
    expect(card.closingIsEstimate, isFalse);
    expect(card.diffRial, 20000 - (-500 - 1000));
  });

  test('کارتی که اولین پیامکش در همین دوره است: اول دوره صفر', () {
    final items = [
      _tx('a', kind: 'expense', amount: 1000, balance: 20000, at: DateTime.utc(2026, 9, 1)),
    ];
    final card = computeBalanceBreakdown(items, _shahrivar).cards.single;
    expect(card.opening, isNull);
    expect(card.openingRial, 0);
    expect(card.diffRial, 21000);
  });

  test('انتقال/بازبینیِ دوره در «خارج از جمع» می‌آید', () {
    final items = [
      _tx('o', kind: 'income', amount: 1, balance: 10000, at: DateTime.utc(2026, 8, 10)),
      _tx('t', kind: 'transfer', amount: 4000, balance: 6000, at: DateTime.utc(2026, 9, 1)),
      _tx('r', kind: 'unknown', amount: 100, balance: 5900, at: DateTime.utc(2026, 9, 2), review: true),
    ];
    final card = computeBalanceBreakdown(items, _shahrivar).cards.single;
    expect(card.uncounted.map((t) => t.id), ['t', 'r']);
    expect(card.diffRial, 5900 - 10000);
  });

  test('تراکنشِ بعد از پایانِ دوره در موجودیِ آخرِ دوره نمی‌آید', () {
    final items = [
      _tx('o', kind: 'income', amount: 1, balance: 10000, at: DateTime.utc(2026, 8, 10)),
      _tx('a', kind: 'expense', amount: 1000, balance: 9000, at: DateTime.utc(2026, 9, 1)),
      _tx('z', kind: 'expense', amount: 5000, balance: 4000, at: DateTime.utc(2026, 10, 1)),
    ];
    final b = computeBalanceBreakdown(items, _shahrivar);
    expect(b.bankClosingRial, 9000);
    expect(b.diffRial, 0);
  });

  test('دو کارت: هر کارت جدا حساب می‌شود و جمع = مجموع', () {
    final items = [
      _tx('o1', kind: 'income', amount: 1, balance: 10000, at: DateTime.utc(2026, 8, 10)),
      _tx('o2', kind: 'income', amount: 1, balance: 3000, at: DateTime.utc(2026, 8, 11), card: '5678'),
      _tx('a', kind: 'expense', amount: 1000, balance: 9000, at: DateTime.utc(2026, 9, 1)),
      _tx('b', kind: 'expense', amount: 500, balance: 2000, at: DateTime.utc(2026, 9, 2), card: '5678'),
    ];
    final b = computeBalanceBreakdown(items, _shahrivar);
    expect(b.cards, hasLength(2));
    expect(b.openingRial, 13000);
    // کارتِ دوم ۵۰۰ ثبت شده ولی مانده ۱۰۰۰ پایین رفته → اختلاف −۵۰۰
    expect(b.diffRial, -500);
    expect(b.cards.first.sample.cardLast4, '5678'); // کارتِ دارای اختلاف اول
  });
}
