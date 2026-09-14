import 'package:economy/core/transfer/transfer_finder.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord tx({
  required String id,
  required String kind,
  int? amount = 150000,
  String? owner,
  String? cardLast4,
  String bankId = 'mellat',
  DateTime? at,
}) {
  final t = at ?? DateTime.utc(2026, 9, 10, 8);
  return TransactionRecord(
    id: id,
    kind: kind,
    amountRial: amount,
    ownerUserId: owner,
    cardLast4: cardLast4,
    bankId: bankId,
    transactionDate: t,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  const finder = TransferFinder();

  test('برداشت + واریزِ هم‌مبلغ بین دو نفر در بازه → یک انتقال', () {
    final pairs = finder.find([
      tx(id: 'out', kind: 'expense', owner: 'father', cardLast4: '1111',
          at: DateTime.utc(2026, 9, 10, 8, 0)),
      tx(id: 'in', kind: 'income', owner: 'mother', cardLast4: '2222',
          at: DateTime.utc(2026, 9, 10, 8, 5)),
    ]);
    expect(pairs.length, 1);
    expect(pairs.single.out.id, 'out');
    expect(pairs.single.inn.id, 'in');
  });

  test('فاصله‌ی زیاد → انتقال نیست', () {
    final pairs = finder.find([
      tx(id: 'out', kind: 'expense', owner: 'father', cardLast4: '1111',
          at: DateTime.utc(2026, 9, 10, 8, 0)),
      tx(id: 'in', kind: 'income', owner: 'mother', cardLast4: '2222',
          at: DateTime.utc(2026, 9, 10, 12, 0)),
    ]);
    expect(pairs, isEmpty);
  });

  test('مبلغِ متفاوت → انتقال نیست', () {
    final pairs = finder.find([
      tx(id: 'out', kind: 'expense', owner: 'father', amount: 150000),
      tx(id: 'in', kind: 'income', owner: 'mother', amount: 200000,
          at: DateTime.utc(2026, 9, 10, 8, 5)),
    ]);
    expect(pairs, isEmpty);
  });

  test('همان کارت (نه دو کارتِ متفاوت) → انتقال نیست', () {
    final pairs = finder.find([
      tx(id: 'out', kind: 'expense', owner: 'me', cardLast4: '1111'),
      tx(id: 'in', kind: 'income', owner: 'me', cardLast4: '1111',
          at: DateTime.utc(2026, 9, 10, 8, 5)),
    ]);
    expect(pairs, isEmpty);
  });

  test('جفتِ نادیده‌گرفته‌شده دوباره پیشنهاد نمی‌شود', () {
    final all = [
      tx(id: 'out', kind: 'expense', owner: 'father', cardLast4: '1111'),
      tx(id: 'in', kind: 'income', owner: 'mother', cardLast4: '2222',
          at: DateTime.utc(2026, 9, 10, 8, 5)),
    ];
    final key = finder.find(all).single.key;
    expect(finder.find(all, dismissed: {key}), isEmpty);
  });
}
