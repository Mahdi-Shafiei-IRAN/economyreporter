/// دادهٔ صفحه‌ی اصلی (طرح ۱۲.۹): تراکنش‌های یک ماه به تفکیکِ عضو و کارت، خلاصه‌ی خالص/درآمد/هزینه/موجودی و
/// گروه‌های روز. خالص و بی‌وابستگی به Flutter؛ صفحه فقط نشانش می‌دهد.
library;

import '../sms/jalali.dart';
import 'ledger_math.dart';
import 'models.dart';

/// کلیدِ عضوِ «من» (همه‌ی حساب‌های خودم، با یا بی‌شناسه‌ی کاربر).
const kMePersonKey = 'me';

/// کلیدِ «عضو» برای حساب‌ها: «من»؛ وگرنه شناسه‌ی کاربر؛ حسابِ بی‌شناسه با نامِ یکی از اعضا مالِ همان عضو،
/// وگرنه با نامش.
String Function(LedgerAccount) personKeys(Iterable<LedgerAccount> accounts, bool Function(LedgerAccount) isMine) {
  final byName = <String, String>{};
  for (final a in accounts) {
    if (!isMine(a) && a.ownerUserId != null) byName.putIfAbsent(a.ownerName.trim(), () => a.ownerUserId!);
  }
  return (a) {
    if (isMine(a)) return kMePersonKey;
    return a.ownerUserId ?? byName[a.ownerName.trim()] ?? 'name:${a.ownerName.trim()}';
  };
}

/// یک تراکنش با حسابش (برای نمای روز به روز).
class DashEntry {
  final Entry entry;
  final LedgerAccount account;
  const DashEntry(this.entry, this.account);
}

/// یک کارت/حساب در ماه.
class CardGroup {
  final LedgerAccount account;

  /// موجودیِ الان (null = نامعلوم).
  final int? balanceRial;

  /// تراکنش‌های همین ماه، جدیدترین اول.
  final List<Entry> entries;
  final int incomeRial;
  final int expenseRial;

  const CardGroup({
    required this.account,
    required this.balanceRial,
    required this.entries,
    required this.incomeRial,
    required this.expenseRial,
  });
}

/// یک عضو با کارت‌هایش.
class PersonGroup {
  final String key;
  final String name;
  final bool isMe;
  final List<CardGroup> cards;

  const PersonGroup({required this.key, required this.name, required this.isMe, required this.cards});

  int get count => cards.fold(0, (s, c) => s + c.entries.length);
  int get incomeRial => cards.fold(0, (s, c) => s + c.incomeRial);
  int get expenseRial => cards.fold(0, (s, c) => s + c.expenseRial);
}

/// یک روز (به وقتِ ایران) در نمای روز به روز.
class DayGroup {
  /// آغازِ روز به UTC.
  final DateTime day;

  /// جدیدترین اول.
  final List<DashEntry> entries;
  final int incomeRial;
  final int expenseRial;

  const DayGroup({required this.day, required this.entries, required this.incomeRial, required this.expenseRial});
}

class Dashboard {
  final DateTime from;
  final DateTime to;

  /// همه‌ی اعضا (برای تراشه‌ها؛ بی‌فیلتر). «من» اول.
  final List<({String key, String name, bool isMe})> people;

  /// کارت‌های عضوِ انتخاب‌شده، یا همه (برای تراشه‌ها؛ بی‌فیلترِ کارت).
  final List<LedgerAccount> cardChoices;

  /// اعضا و کارت‌هایی که با فیلتر نشان داده می‌شوند.
  final List<PersonGroup> shown;

  /// روزهای ماه با تراکنش (با همان فیلتر)، جدیدترین اول.
  final List<DayGroup> days;

  final int incomeRial;
  final int expenseRial;

  /// جمعِ موجودیِ الانِ کارت‌های نشان‌داده (فقط معلوم‌ها)؛ null = هیچ‌کدام معلوم نیست.
  final int? balanceRial;

  /// کارت‌هایی که موجودی‌شان نامعلوم است.
  final int unknownBalances;

  const Dashboard({
    required this.from,
    required this.to,
    required this.people,
    required this.cardChoices,
    required this.shown,
    required this.days,
    required this.incomeRial,
    required this.expenseRial,
    required this.balanceRial,
    required this.unknownBalances,
  });

  int get netRial => incomeRial - expenseRial;
  int get count => shown.fold(0, (s, p) => s + p.count);
}

/// [accounts]: حساب‌های نشان‌دادنی (کنارگذاشته‌ها نه). [personKey]/[accountId]: فیلتر؛ کارتی که مالِ عضوِ
/// انتخاب‌شده نیست نادیده گرفته می‌شود. [meName]: نامِ «من» (وگرنه نامِ صاحبِ اولین حسابِ خودم).
Dashboard buildDashboard({
  required List<LedgerAccount> accounts,
  required Map<String, List<LedgerItem>> ledgers,
  required bool Function(LedgerAccount) isMine,
  required DateTime from,
  required DateTime to,
  String? personKey,
  String? accountId,
  String? meName,
}) {
  // اعضا: «من» اول، بعد به ترتیبِ نام.
  final personKeyOf = personKeys(accounts, isMine);
  final names = <String, ({String key, String name, bool isMe})>{};
  for (final a in accounts) {
    final k = personKeyOf(a);
    final isMe = k == kMePersonKey;
    names[k] ??= (key: k, name: (isMe ? meName?.trim() : null) ?? a.ownerName.trim(), isMe: isMe);
  }
  final people = names.values.toList()
    ..sort((x, y) {
      if (x.isMe != y.isMe) return x.isMe ? -1 : 1;
      return x.name.compareTo(y.name);
    });

  final person = people.any((p) => p.key == personKey) ? personKey : null;
  final cardChoices = [for (final a in accounts) if (person == null || personKeyOf(a) == person) a];
  final card = cardChoices.any((a) => a.id == accountId) ? accountId : null;

  bool inMonth(Entry e) => !e.isDeleted && !e.occurredAt.isBefore(from) && e.occurredAt.isBefore(to);

  final groups = <String, List<CardGroup>>{};
  final all = <DashEntry>[];
  var income = 0, expense = 0, unknown = 0;
  int? balance;
  for (final a in cardChoices) {
    if (card != null && a.id != card) continue;
    final seq = ledgers[a.id] ?? const <LedgerItem>[];
    final entries = [
      for (final i in seq)
        if (i is EntryItem && inMonth(i.entry)) i.entry,
    ].reversed.toList();
    final t = periodTotals(entries, from, to);
    final b = currentBalance(seq)?.balanceRial;
    if (b == null) {
      unknown++;
    } else {
      balance = (balance ?? 0) + b;
    }
    income += t.income;
    expense += t.expense;
    groups.putIfAbsent(personKeyOf(a), () => []).add(CardGroup(
          account: a,
          balanceRial: b,
          entries: entries,
          incomeRial: t.income,
          expenseRial: t.expense,
        ));
    all.addAll([for (final e in entries) DashEntry(e, a)]);
  }

  final shown = [
    for (final p in people)
      if (groups[p.key] != null) PersonGroup(key: p.key, name: p.name, isMe: p.isMe, cards: groups[p.key]!),
  ];

  // روز به روز (به وقتِ ایران)، جدیدترین اول.
  all.sort((x, y) => y.entry.occurredAt.compareTo(x.entry.occurredAt));
  final days = <DayGroup>[];
  DateTime? currentDay;
  var bucket = <DashEntry>[];
  void flush() {
    if (currentDay == null) return;
    final t = periodTotals([for (final d in bucket) d.entry], from, to);
    days.add(DayGroup(day: currentDay, entries: bucket, incomeRial: t.income, expenseRial: t.expense));
  }

  for (final d in all) {
    final day = JalaliDate.fromDateTime(d.entry.occurredAt).toUtcStart();
    if (day != currentDay) {
      flush();
      currentDay = day;
      bucket = [];
    }
    bucket.add(d);
  }
  flush();

  return Dashboard(
    from: from,
    to: to,
    people: people,
    cardChoices: cardChoices,
    shown: shown,
    days: days,
    incomeRial: income,
    expenseRial: expense,
    balanceRial: balance,
    unknownBalances: unknown,
  );
}
