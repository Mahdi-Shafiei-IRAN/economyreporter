import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/tx_query.dart';
import 'package:flutter_test/flutter_test.dart';

TransactionRecord _t(
  String id, {
  String kind = 'expense',
  int amount = 1000,
  int day = 1,
  int hour = 12,
  String? owner,
  String? wallet,
  String? card,
  String? counterparty,
  bool review = false,
}) {
  final at = DateTime.utc(2026, 9, day, hour);
  return TransactionRecord(
    id: id,
    kind: kind,
    amountRial: amount,
    bankId: 'mellat',
    cardLast4: card,
    ownerName: owner,
    walletLabel: wallet,
    counterparty: counterparty,
    needsReview: review,
    transactionDate: at,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('مرتب‌سازی', () {
    final items = [
      _t('a', amount: 5000, day: 2),
      _t('b', amount: 9000, day: 1),
      _t('c', amount: 1000, day: 3),
    ];

    test('پیش‌فرض: جدیدترین اول', () {
      expect(applyQuery(items).map((t) => t.id), ['c', 'a', 'b']);
    });

    test('قدیمی‌ترین، بیشترین و کمترین مبلغ', () {
      expect(applyQuery(items, sort: TxSort.oldest).map((t) => t.id), ['b', 'a', 'c']);
      expect(applyQuery(items, sort: TxSort.amountDesc).map((t) => t.id), ['b', 'a', 'c']);
      expect(applyQuery(items, sort: TxSort.amountAsc).map((t) => t.id), ['c', 'a', 'b']);
    });

    test('مبلغ برابر → جدیدتر اول', () {
      final same = [_t('x', amount: 10, day: 1), _t('y', amount: 10, day: 5)];
      expect(applyQuery(same, sort: TxSort.amountDesc).map((t) => t.id), ['y', 'x']);
    });
  });

  group('فیلتر', () {
    final items = [
      _t('in', kind: 'income', owner: 'بابا'),
      _t('ex', kind: 'expense', owner: 'مامان', counterparty: 'نانوایی'),
      _t('tr', kind: 'transfer'),
    ];

    test('نوع', () {
      expect(applyQuery(items, kind: KindFilter.income).map((t) => t.id), ['in']);
      expect(applyQuery(items, kind: KindFilter.transfer).map((t) => t.id), ['tr']);
    });

    test('شخص (و «نامشخص» برای کارتِ بی‌صاحب)', () {
      expect(applyQuery(items, person: 'مامان').map((t) => t.id), ['ex']);
      expect(applyQuery(items, person: kUnknownPerson).map((t) => t.id), ['tr']);
    });

    test('جستجو با ارقام فارسی هم کار می‌کند', () {
      expect(applyQuery(items, search: 'نان').map((t) => t.id), ['ex']);
      // مبلغ ۱۰۰۰ ریال = ۱۰۰ تومان
      expect(applyQuery(items, search: '۱۰۰'), hasLength(3));
    });
  });

  group('گروه‌بندی پله‌ای شخص ← کارت ← تراکنش', () {
    test('ترتیب افراد، کارت‌ها و جمع هر گروه', () {
      final items = applyQuery([
        _t('1', owner: 'مامان', wallet: 'کارت خانه', card: '1111', amount: 3000, day: 3),
        _t('2', owner: 'بابا', wallet: 'کارت حقوق', card: '2222', amount: 2000, day: 2),
        _t('3', owner: 'بابا', card: '9999', amount: 7000, day: 4), // کارت ثبت‌نشده
        _t('4', owner: 'بابا', wallet: 'کارت حقوق', card: '2222', kind: 'income', amount: 50000, day: 1),
        _t('5', card: '5555', amount: 100, day: 5), // صاحب نامشخص
        _t('6', owner: 'بابا', wallet: 'کارت حقوق', card: '2222', amount: 999, review: true),
      ]);

      final groups = groupByPerson(items);
      expect(groups.map((g) => g.name), ['بابا', 'مامان', kUnknownPerson]);

      final baba = groups.first;
      expect(baba.count, 4);
      expect(baba.cards.map((c) => c.title), ['کارت حقوق', 'بانک ملت • کارت ۹۹۹۹']);
      expect(baba.cards.first.registered, isTrue);
      expect(baba.cards.first.details, 'بانک ملت • کارت ۲۲۲۲');
      expect(baba.cards.last.registered, isFalse);
      // ترتیب داخل کارت همان ترتیب مرتب‌سازی است (جدیدترین اول)
      expect(baba.cards.first.items.map((t) => t.id), ['2', '4', '6']);
      // منتظر بازبینی در جمع نمی‌آید
      expect(baba.summary.expenseRial, 2000 + 7000);
      expect(baba.summary.incomeRial, 50000);
    });

    test('گروه‌بندی روزانه پیاپی است', () {
      final items = applyQuery([
        _t('a', day: 1, hour: 9),
        _t('b', day: 1, hour: 18),
        _t('c', day: 2),
      ]);
      final days = groupByDay(items);
      expect(days, hasLength(2));
      expect(days.first.items.map((t) => t.id), ['c']);
      expect(days.last.items.map((t) => t.id), ['b', 'a']);
    });
  });
}
