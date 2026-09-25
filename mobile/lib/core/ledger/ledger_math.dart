/// حسابِ موجودی و اختلاف (docs/v2-design.md بخش ۶). همه‌چیز روی یک **فهرستِ مرتب**
/// از تراکنش‌ها و نقطه‌های مانده کار می‌کند، نه روی مقایسه‌ی زمان (پیامک فقط تا دقیقه زمان دارد).
library;

import 'models.dart';

sealed class LedgerItem {
  const LedgerItem();
  DateTime get at;
  String get accountId;

  /// موجودیِ قطعی بعد از این قلم، اگر نقطه‌ی مانده است.
  int? get checkpointBalance;
  int get signed;
}

class EntryItem extends LedgerItem {
  final Entry entry;
  const EntryItem(this.entry);
  @override
  DateTime get at => entry.occurredAt;
  @override
  String get accountId => entry.accountId;
  @override
  int? get checkpointBalance => entry.bankBalanceAfter;
  @override
  int get signed => entry.signed;
}

class CheckpointItem extends LedgerItem {
  final Checkpoint checkpoint;
  const CheckpointItem(this.checkpoint);
  @override
  DateTime get at => checkpoint.at;
  @override
  String get accountId => checkpoint.accountId;
  @override
  int? get checkpointBalance => checkpoint.balanceRial;
  @override
  int get signed => 0;
}

int _byTime(Entry a, Entry b) {
  var c = a.occurredAt.compareTo(b.occurredAt);
  if (c != 0) return c;
  c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

bool _fitsAfter(int prev, Entry e) =>
    e.bankBalanceAfter != null && prev + e.signed == e.bankBalanceAfter;

/// ترتیبِ تراکنش‌های یک حساب: زمان؛ و پیامک‌های هم‌دقیقه به ترتیبی که مانده‌هایشان پشتِ هم
/// جور شود (منطقِ `sortForBalance` نسخه‌ی ۱).
void sortEntriesForBalance(List<Entry> list) {
  list.sort(_byTime);
  int? prev;
  var i = 0;
  while (i < list.length) {
    var j = i + 1;
    while (j < list.length && list[j].occurredAt == list[i].occurredAt) {
      j++;
    }
    if (j - i > 1) list.setRange(i, j, _chainRun(list.sublist(i, j), prev));
    for (var k = i; k < j; k++) {
      prev = list[k].bankBalanceAfter ?? (prev == null ? null : prev + list[k].signed);
    }
    i = j;
  }
}

List<Entry> _chainRun(List<Entry> run, int? prev) {
  (List<Entry>, int) greedy(int? start, List<Entry> items) {
    final rest = [...items];
    final out = <Entry>[];
    var p = start;
    var fits = 0;
    while (rest.isNotEmpty) {
      var k = p == null ? -1 : rest.indexWhere((e) => _fitsAfter(p!, e));
      if (k == -1) {
        k = 0;
      } else {
        fits++;
      }
      final e = rest.removeAt(k);
      out.add(e);
      p = e.bankBalanceAfter ?? (p == null ? null : p + e.signed);
    }
    return (out, fits);
  }

  if (prev != null) return greedy(prev, run).$1;
  var best = run;
  var bestFits = -1;
  for (var s = 0; s < run.length; s++) {
    final first = run[s];
    if (first.bankBalanceAfter == null) continue;
    final (tail, fits) = greedy(first.bankBalanceAfter, [...run]..removeAt(s));
    if (fits > bestFits) {
      best = [first, ...tail];
      bestFits = fits;
    }
  }
  return best;
}

/// فهرستِ مرتبِ یک حساب. نقطه‌ی دستی بعد از همه‌ی تراکنش‌هایی می‌نشیند که
/// `occurredAt ≤ at` دارند؛ نقطه‌ی بانکی همان تراکنشِ مانده‌دار است.
List<LedgerItem> orderLedger(Iterable<Entry> entries, Iterable<Checkpoint> checkpoints) {
  final es = [for (final e in entries) if (!e.isDeleted) e];
  sortEntriesForBalance(es);
  final cps = [for (final c in checkpoints) if (c.deletedAt == null) c]..sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
  final out = <LedgerItem>[];
  var j = 0;
  for (final e in es) {
    while (j < cps.length && cps[j].at.isBefore(e.occurredAt)) {
      out.add(CheckpointItem(cps[j++]));
    }
    out.add(EntryItem(e));
  }
  while (j < cps.length) {
    out.add(CheckpointItem(cps[j++]));
  }
  return out;
}

class AccountBalance {
  final int balanceRial;

  /// آخرین نقطه‌ی مانده (مبنای عدد؛ I3).
  final LedgerItem anchor;
  const AccountBalance(this.balanceRial, this.anchor);
}

/// موجودی = آخرین نقطه‌ی مانده + تراکنش‌های بعد از آن. بدونِ هیچ نقطه‌ای: null.
AccountBalance? currentBalance(List<LedgerItem> seq) {
  for (var k = seq.length - 1; k >= 0; k--) {
    final b = seq[k].checkpointBalance;
    if (b == null) continue;
    var sum = 0;
    for (var i = k + 1; i < seq.length; i++) {
      sum += seq[i].signed;
    }
    return AccountBalance(b + sum, seq[k]);
  }
  return null;
}

/// بازه‌ی بینِ دو نقطه‌ی مانده‌ی پشتِ‌سرِ‌هم که جمعِ تراکنش‌هایش با مانده‌ها نمی‌خواند.
class DiscrepancyWindow {
  final LedgerItem from;
  final LedgerItem to;
  final int expectedRial;
  final int actualRial;

  /// تراکنش‌های داخلِ بازه (شاملِ تراکنشِ نقطه‌ی پایانی اگر بانکی است).
  final List<Entry> entries;

  const DiscrepancyWindow({
    required this.from,
    required this.to,
    required this.expectedRial,
    required this.actualRial,
    required this.entries,
  });

  String get accountId => to.accountId;
  int get diffRial => actualRial - expectedRial;
  DateTime get start => from.at;
  DateTime get end => to.at;
}

List<DiscrepancyWindow> discrepancies(List<LedgerItem> seq) {
  final out = <DiscrepancyWindow>[];
  LedgerItem? prev;
  var sum = 0;
  var inside = <Entry>[];
  for (final item in seq) {
    if (item is EntryItem) {
      sum += item.signed;
      inside.add(item.entry);
    }
    final bal = item.checkpointBalance;
    if (bal == null) continue;
    if (prev != null) {
      final expected = prev.checkpointBalance! + sum;
      if (expected != bal) {
        out.add(DiscrepancyWindow(
            from: prev, to: item, expectedRial: expected, actualRial: bal, entries: inside));
      }
    }
    prev = item;
    sum = 0;
    inside = <Entry>[];
  }
  return out;
}

/// موجودی درست بعد از همه‌ی اقلامِ تا [t] ([inclusive]=false: فقط قبل از [t]).
/// [backwardFirst]: اول رو به عقب از نزدیک‌ترین نقطه‌ی بعد (موجودیِ اولِ ماه، طرح ۶.۱)،
/// وگرنه رو به جلو از نقطه‌ی قبل؛ با false برعکس (مانده‌ی زنجیره پیش از یک پیامکِ تازه).
int? balanceAt(List<LedgerItem> seq, DateTime t,
    {bool inclusive = true, bool backwardFirst = true}) {
  var p = 0;
  while (p < seq.length && (inclusive ? !seq[p].at.isAfter(t) : seq[p].at.isBefore(t))) {
    p++;
  }
  int? backward() {
    for (var k = p; k < seq.length; k++) {
      final b = seq[k].checkpointBalance;
      if (b == null) continue;
      var sum = 0;
      for (var i = p; i <= k; i++) {
        sum += seq[i].signed;
      }
      return b - sum;
    }
    return null;
  }

  int? forward() {
    for (var k = p - 1; k >= 0; k--) {
      final b = seq[k].checkpointBalance;
      if (b == null) continue;
      var sum = 0;
      for (var i = k + 1; i < p; i++) {
        sum += seq[i].signed;
      }
      return b + sum;
    }
    return null;
  }

  return backwardFirst ? (backward() ?? forward()) : (forward() ?? backward());
}
