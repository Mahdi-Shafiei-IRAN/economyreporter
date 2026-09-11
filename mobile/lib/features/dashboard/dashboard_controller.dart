/// کنترلر داشبورد: بارگذاری جمع و لیست تراکنش‌ها و افزودن از پیامک.
library;

import 'package:flutter/foundation.dart' hide Category;

import '../../core/reconcile/reconciliation.dart';
import '../../core/sms/sms_parser.dart';
import '../categories/data/category.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';
import '../wallets/data/wallet.dart';

class DashboardController extends ChangeNotifier {
  final TransactionStore repository;
  final SmsParser parser;

  DashboardController(this.repository, {this.parser = const SmsParser()});

  bool loading = true;
  FinanceSummary summary = const FinanceSummary(incomeRial: 0, expenseRial: 0);
  List<TransactionRecord> transactions = const [];
  int needsReviewCount = 0;
  List<BalanceGap> balanceGaps = const [];
  List<TransactionRecord> uncategorized = const [];
  List<Wallet> wallets = const [];

  List<TransactionRecord> get reviewItems =>
      transactions.where((t) => t.needsReview).toList();

  int get uncategorizedCount => uncategorized.length;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    summary = await repository.summary();
    transactions = await repository.getAll(limit: 200);
    needsReviewCount = await repository.needsReviewCount();
    balanceGaps = const ReconciliationService().findGaps(transactions);
    uncategorized = await repository.uncategorized(limit: 200);
    wallets = await repository.wallets();
    loading = false;
    notifyListeners();
  }

  /// کیفِ متناظر با کارت/حساب یک تراکنش (اگر ثبت شده باشد).
  Wallet? walletFor(TransactionRecord t) {
    for (final w in wallets) {
      if (w.matches(cardLast4: t.cardLast4, accountRef: t.accountRef)) return w;
    }
    return null;
  }

  Future<void> addWallet(Wallet wallet) async {
    await repository.addWallet(wallet);
    await load();
  }

  Future<void> deleteWallet(String id) async {
    await repository.deleteWallet(id);
    await load();
  }

  Future<TransactionRecord?> transactionById(String id) =>
      repository.getById(id);

  Future<List<Category>> categories() => repository.categories();

  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to}) =>
      repository.categoryTotals(from: from, to: to);

  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  }) async {
    await repository.categorize(transactionId, categoryIds,
        description: description);
    await load();
  }

  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    await repository.updateTransaction(
      id,
      kind: kind,
      amountRial: amountRial,
      counterparty: counterparty,
      description: description,
      needsReview: needsReview,
    );
    await load();
  }

  /// تأیید یک تراکنش در صف بازبینی: نوع نهایی + پاک‌کردن پرچم بازبینی.
  Future<void> confirmReview(String id, {String? kind}) async {
    await updateTransaction(id, kind: kind, needsReview: false);
  }

  Future<void> deleteTransaction(String id) async {
    await repository.deleteTransaction(id);
    await load();
  }

  /// یک پیامک را پارس و ذخیره می‌کند و سپس داشبورد را تازه‌سازی می‌کند.
  Future<TxInsertOutcome> addFromSms({
    required String sender,
    required String body,
  }) async {
    final parsed = parser.parse(sender: sender, body: body);
    final outcome = await repository.saveParsed(
      parsed,
      sender: sender,
      receivedAt: DateTime.now(),
    );
    await load();
    return outcome;
  }
}
