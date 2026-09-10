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

  Future<void> load() async {
    loading = true;
    notifyListeners();
    summary = await repository.summary();
    transactions = await repository.getAll(limit: 200);
    loading = false;
    notifyListeners();
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
