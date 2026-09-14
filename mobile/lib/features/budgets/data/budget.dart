/// بودجه: سقفِ خرجِ ماهانه برای یک دسته (بر اساسِ نامِ دسته).
library;

class Budget {
  final String id;
  final String categoryName;
  final String period; // فعلاً فقط 'monthly'
  final int limitRial;

  const Budget({
    required this.id,
    required this.categoryName,
    required this.limitRial,
    this.period = 'monthly',
  });

  Budget copyWith({String? categoryName, int? limitRial, String? period}) => Budget(
        id: id,
        categoryName: categoryName ?? this.categoryName,
        limitRial: limitRial ?? this.limitRial,
        period: period ?? this.period,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'category_name': categoryName,
        'period': period,
        'limit_rial': limitRial,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as String,
        categoryName: m['category_name'] as String,
        period: (m['period'] as String?) ?? 'monthly',
        limitRial: (m['limit_rial'] as num).toInt(),
      );
}

/// بودجه + مقدارِ خرج‌شده‌ی همان دسته در بازه‌ی جاری.
class BudgetUsage {
  final Budget budget;
  final int spentRial;

  const BudgetUsage({required this.budget, required this.spentRial});

  int get limitRial => budget.limitRial;
  String get categoryName => budget.categoryName;
  int get remainingRial => limitRial - spentRial;
  double get ratio => limitRial <= 0 ? 0 : spentRial / limitRial;
  bool get exceeded => spentRial > limitRial;
}
