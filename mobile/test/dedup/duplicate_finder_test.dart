import 'package:economy/core/dedup/duplicate_finder.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord tx({
  required String id,
  String kind = 'income',
  int? amount = 100000,
  String? bankId = 'mellat',
  String? cardLast4 = '1234',
  DateTime? at,
  bool deleted = false,
  bool needsReview = false,
}) {
  final t = at ?? DateTime.utc(2026, 9, 10, 8);
  return TransactionRecord(
    id: id,
    kind: kind,
    amountRial: amount,
    bankId: bankId,
    cardLast4: cardLast4,
    transactionDate: t,
    createdAt: t,
    updatedAt: t,
    deletedAt: deleted ? t : null,
    needsReview: needsReview,
  );
}

void main() {
  const finder = DuplicateFinder();

  test('دو درآمدِ هم‌مبلغ/هم‌کارت در بازه → یک گروهِ دوتایی', () {
    final groups = finder.find([
      tx(id: 'a', at: DateTime.utc(2026, 9, 10, 8, 0)),
      tx(id: 'b', at: DateTime.utc(2026, 9, 10, 8, 30)),
    ]);
    expect(groups.length, 1);
    expect(groups.single.items.length, 2);
    expect(groups.single.keep.id, 'a'); // قدیمی‌تر می‌ماند
    expect(groups.single.extras.map((t) => t.id), ['b']);
  });

  test('فاصله‌ی بیش از پنجره → تکراری نیست', () {
    final groups = finder.find([
      tx(id: 'a', at: DateTime.utc(2026, 9, 10, 8)),
      tx(id: 'b', at: DateTime.utc(2026, 9, 10, 20)),
    ]);
    expect(groups, isEmpty);
  });

  test('کارت متفاوت یا مبلغ متفاوت → گروه نمی‌شود', () {
    final groups = finder.find([
      tx(id: 'a', cardLast4: '1234'),
      tx(id: 'b', cardLast4: '5678'),
      tx(id: 'c', amount: 200000),
    ]);
    expect(groups, isEmpty);
  });

  test('حذف‌شده/نیازمند بازبینی/بدون‌مبلغ نادیده گرفته می‌شوند', () {
    final groups = finder.find([
      tx(id: 'a'),
      tx(id: 'b', deleted: true),
      tx(id: 'c', needsReview: true),
      tx(id: 'd', amount: null),
    ]);
    expect(groups, isEmpty);
  });

  test('گروهِ نادیده‌گرفته‌شده (تکراری نیست) دوباره پیشنهاد نمی‌شود', () {
    final all = [
      tx(id: 'a', at: DateTime.utc(2026, 9, 10, 8, 0)),
      tx(id: 'b', at: DateTime.utc(2026, 9, 10, 8, 30)),
    ];
    final key = finder.find(all).single.key;
    final groups = finder.find(all, dismissed: {key});
    expect(groups, isEmpty);
  });

  test('بزرگ‌ترین مبلغ اول', () {
    final groups = finder.find([
      tx(id: 'a1', amount: 100000, cardLast4: '1111'),
      tx(id: 'a2', amount: 100000, cardLast4: '1111', at: DateTime.utc(2026, 9, 10, 8, 10)),
      tx(id: 'b1', amount: 500000, cardLast4: '2222'),
      tx(id: 'b2', amount: 500000, cardLast4: '2222', at: DateTime.utc(2026, 9, 10, 8, 10)),
    ]);
    expect(groups.length, 2);
    expect(groups.first.amountRial, 500000);
  });
}
