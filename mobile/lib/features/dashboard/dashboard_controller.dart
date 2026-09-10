/// کنترلر داشبورد: بارگذاری جمع و لیست تراکنش‌ها و افزودن از پیامک.
library;

import 'package:flutter/foundation.dart';

import '../../core/sms/sms_parser.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';

class DashboardController extends ChangeNotifier {
  final TransactionStore repository;
  final SmsParser parser;

  DashboardController(this.repository, {this.parser = const SmsParser()});

  bool loading = true;
  FinanceSummary summary = const FinanceSummary(incomeRial: 0, expenseRial: 0);
  List<TransactionRecord> transactions = const [];
  int needsReviewCount = 0;

  List<TransactionRecord> get reviewItems =>
      transactions.where((t) => t.needsReview).toList();

  Future<void> load() async {
    loading = true;
    notifyListeners();
    summary = await repository.summary();
    transactions = await repository.getAll(limit: 200);
    needsReviewCount = await repository.needsReviewCount();
    loading = false;
    notifyListeners();
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
