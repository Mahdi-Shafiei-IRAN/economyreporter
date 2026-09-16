/// مرتب‌سازی، فیلتر و گروه‌بندی تراکنش‌ها برای صفحه‌ی اصلی (منطق خالص و تست‌پذیر).
library;

import '../../../core/format/money_format.dart';
import '../../../core/sms/bank_registry.dart';
import '../../../core/sms/digit_utils.dart';
import '../../../core/sms/jalali.dart';
import 'transaction_record.dart';
import 'transaction_repository.dart';

enum TxSort { newest, oldest, amountDesc, amountAsc }

extension TxSortLabel on TxSort {
  String get label => switch (this) {
        TxSort.newest => 'جدیدترین',
        TxSort.oldest => 'قدیمی‌ترین',
        TxSort.amountDesc => 'بیشترین مبلغ',
        TxSort.amountAsc => 'کمترین مبلغ',
      };

  bool get byDate => this == TxSort.newest || this == TxSort.oldest;
}

enum KindFilter { all, income, expense, transfer }

extension KindFilterLabel on KindFilter {
  String get label => switch (this) {
        KindFilter.all => 'همه‌ی انواع',
        KindFilter.income => 'فقط درآمد',
        KindFilter.expense => 'فقط هزینه',
        KindFilter.transfer => 'فقط انتقال',
      };

  bool matches(TransactionRecord t) => this == KindFilter.all || t.kind == name;
}

const String kUnknownPerson = 'نامشخص';

/// نام صاحب برای گروه‌بندی («نامشخص» اگر کارت هنوز به کسی وصل نشده).
String personOf(TransactionRecord t) {
  final name = t.ownerName?.trim();
  return (name == null || name.isEmpty) ? kUnknownPerson : name;
}

/// کلید کارت/حساب داخل یک شخص.
String cardKeyOf(TransactionRecord t) {
  final label = t.walletLabel?.trim();
  if (label != null && label.isNotEmpty) return 'w:$label';
  return 'c:${t.bankId ?? ''}|${t.cardLast4 ?? t.accountRef ?? ''}';
}

/// «بانک ملت • کارت ۱۲۳۴» (یا null اگر هیچ اطلاعی نیست).
String? cardDetailsOf(TransactionRecord t) {
  final parts = [
    if (t.bankId != null) bankNameById(t.bankId!),
    if (t.cardLast4 != null)
      'کارت ${toPersianDigits(t.cardLast4!)}'
    else if (t.accountRef != null)
      'حساب ${toPersianDigits(t.accountRef!)}',
  ];
  return parts.isEmpty ? null : parts.join(' • ');
}

/// عنوان کارت: برچسب کیف («کارت حقوق») وگرنه بانک و ۴ رقم.
String cardTitleOf(TransactionRecord t) {
  final label = t.walletLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return cardDetailsOf(t) ?? 'کارت/حساب نامشخص';
}

int _compare(TransactionRecord a, TransactionRecord b, TxSort sort) {
  switch (sort) {
    case TxSort.newest:
      return b.effectiveTime.compareTo(a.effectiveTime);
    case TxSort.oldest:
      return a.effectiveTime.compareTo(b.effectiveTime);
    case TxSort.amountDesc:
      final c = (b.amountRial ?? 0).compareTo(a.amountRial ?? 0);
      return c != 0 ? c : b.effectiveTime.compareTo(a.effectiveTime);
    case TxSort.amountAsc:
      final c = (a.amountRial ?? 0).compareTo(b.amountRial ?? 0);
      return c != 0 ? c : b.effectiveTime.compareTo(a.effectiveTime);
  }
}

/// مرتب‌سازی پایدار (ترتیب موارد برابر حفظ می‌شود).
List<TransactionRecord> sortTransactions(Iterable<TransactionRecord> items, TxSort sort) {
  final indexed = items.toList().asMap().entries.toList()
    ..sort((x, y) {
      final c = _compare(x.value, y.value, sort);
      return c != 0 ? c : x.key.compareTo(y.key);
    });
  return [for (final e in indexed) e.value];
}

bool _matchesSearch(TransactionRecord t, String query) {
  final q = normalizeDigits(query.trim());
  if (q.isEmpty) return true;
  final haystack = [
    t.counterparty,
    t.description,
    t.ownerName,
    t.walletLabel,
    if (t.bankId != null) bankNameById(t.bankId!),
    t.cardLast4,
    t.accountRef,
    if (t.amountRial != null) '${t.amountRial! ~/ 10}',
    for (final a in t.allocations) a.categoryName,
  ].whereType<String>().map(normalizeDigits);
  return haystack.any((h) => h.contains(q));
}

/// فیلتر + مرتب‌سازی فهرست تراکنش‌ها.
List<TransactionRecord> applyQuery(
  Iterable<TransactionRecord> items, {
  TxSort sort = TxSort.newest,
  KindFilter kind = KindFilter.all,
  String? person,
  String search = '',
}) {
  return sortTransactions(
    items.where((t) =>
        !t.isDeleted &&
        kind.matches(t) &&
        (person == null || personOf(t) == person) &&
        _matchesSearch(t, search)),
    sort,
  );
}

/// یک کارت/حساب و تراکنش‌هایش.
class CardGroup {
  final String key;
  final String title;

  /// بانک و ۴ رقم (وقتی عنوان، برچسب کیف است).
  final String? details;
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;

  /// آیا این کارت در «کارت‌ها و حساب‌ها» به صاحبی وصل شده؟
  final bool registered;
  final List<TransactionRecord> items;

  const CardGroup({
    required this.key,
    required this.title,
    required this.items,
    required this.registered,
    this.details,
    this.bankId,
    this.cardLast4,
    this.accountRef,
  });

  FinanceSummary get summary => FinanceSummary.of(items);

  /// آیا صاحبِ این کارت از قبل مشخص است؟ (کیفِ ثبت‌شده، یا صاحبِ فرستنده).
  /// اگر بله، دیگر «تعیین صاحب» لازم نیست.
  bool get hasOwner =>
      registered ||
      items.any((t) => (t.ownerName?.trim().isNotEmpty ?? false));
}

/// گزارشِ یک کارت: موجودیِ واقعی + درآمد/هزینهٔ دوره + تراکنش‌های همان دوره.
class CardReport {
  final String key;
  final String title;
  final String owner;
  final String? details;

  /// موجودیِ واقعی از «مانده»ی پیامک‌ها؛ null یعنی این کارت مانده‌ای در پیامک ندارد.
  final int? balanceRial;
  final int incomeRial;
  final int expenseRial;
  final List<TransactionRecord> items;

  const CardReport({
    required this.key,
    required this.title,
    required this.owner,
    required this.incomeRial,
    required this.expenseRial,
    required this.items,
    this.details,
    this.balanceRial,
  });

  int get netRial => incomeRial - expenseRial;
}

/// یک شخص، کارت‌هایش، و تراکنش‌های هر کارت.
class PersonGroup {
  final String name;
  final List<CardGroup> cards;

  const PersonGroup({required this.name, required this.cards});

  bool get isUnknown => name == kUnknownPerson;
  int get count => cards.fold(0, (a, c) => a + c.items.length);
  FinanceSummary get summary => FinanceSummary.of(cards.expand((c) => c.items));
}

/// گروه‌بندی پله‌ای: شخص → کارت → تراکنش‌ها (ترتیب تراکنش‌ها حفظ می‌شود).
/// افراد به‌ترتیب نام، «نامشخص» آخر؛ کارت‌های ثبت‌شده اول.
List<PersonGroup> groupByPerson(List<TransactionRecord> sorted) {
  final byPerson = <String, Map<String, List<TransactionRecord>>>{};
  for (final t in sorted) {
    byPerson
        .putIfAbsent(personOf(t), () => {})
        .putIfAbsent(cardKeyOf(t), () => [])
        .add(t);
  }

  final people = <PersonGroup>[];
  byPerson.forEach((name, cards) {
    final groups = cards.entries.map((e) {
      final first = e.value.first;
      final registered = e.key.startsWith('w:');
      return CardGroup(
        key: e.key,
        title: cardTitleOf(first),
        details: registered ? cardDetailsOf(first) : null,
        bankId: first.bankId,
        cardLast4: first.cardLast4,
        accountRef: first.accountRef,
        registered: registered,
        items: e.value,
      );
    }).toList()
      ..sort((a, b) {
        if (a.registered != b.registered) return a.registered ? -1 : 1;
        return a.title.compareTo(b.title);
      });
    people.add(PersonGroup(name: name, cards: groups));
  });
  people.sort((a, b) {
    if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
    return a.name.compareTo(b.name);
  });
  return people;
}

/// تراکنش‌های یک روز (برای سرتیترِ روز در نمای «همه»).
class DayGroup {
  final JalaliDate day;
  final DateTime anchor;
  final List<TransactionRecord> items;

  const DayGroup({required this.day, required this.anchor, required this.items});

  FinanceSummary get summary => FinanceSummary.of(items);
}

/// گروه‌بندی پیاپی بر اساس روز شمسی (فهرست باید به‌ترتیب تاریخ باشد).
List<DayGroup> groupByDay(List<TransactionRecord> sorted) {
  final groups = <DayGroup>[];
  for (final t in sorted) {
    final day = JalaliDate.fromDateTime(t.effectiveTime);
    if (groups.isNotEmpty && groups.last.day == day) {
      groups.last.items.add(t);
    } else {
      groups.add(DayGroup(day: day, anchor: t.effectiveTime, items: [t]));
    }
  }
  return groups;
}
