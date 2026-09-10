/// مدل خلاصه‌ی داشبورد خانواده (از سرور). همه‌ی مبالغ به ریال.
library;

class MemberExpense {
  final String id;
  final String name;
  final int expensesRial;

  const MemberExpense({required this.id, required this.name, required this.expensesRial});

  factory MemberExpense.fromJson(Map<String, dynamic> j) => MemberExpense(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        expensesRial: (j['expenses'] as num?)?.toInt() ?? 0,
      );
}

class CategoryExpense {
  final String? name;
  final int amountRial;

  const CategoryExpense({required this.name, required this.amountRial});

  factory CategoryExpense.fromJson(Map<String, dynamic> j) => CategoryExpense(
        name: j['name'] as String?,
        amountRial: (j['amount'] as num?)?.toInt() ?? 0,
      );
}

class CardExpense {
  final String? cardLast4;
  final int amountRial;

  const CardExpense({required this.cardLast4, required this.amountRial});

  factory CardExpense.fromJson(Map<String, dynamic> j) => CardExpense(
        cardLast4: j['card_last4'] as String?,
        amountRial: (j['amount'] as num?)?.toInt() ?? 0,
      );
}

class DashboardSummary {
  final int incomeRial;
  final int expenseRial;
  final int balanceRial;
  final List<MemberExpense> members;
  final List<CategoryExpense> categories;
  final List<CardExpense> cards;

  const DashboardSummary({
    required this.incomeRial,
    required this.expenseRial,
    required this.balanceRial,
    required this.members,
    required this.categories,
    required this.cards,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> j) {
    final family = Map<String, dynamic>.from(j['family'] as Map);
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? [])
            .map((e) => f(Map<String, dynamic>.from(e as Map)))
            .toList();
    return DashboardSummary(
      incomeRial: (family['income'] as num?)?.toInt() ?? 0,
      expenseRial: (family['expenses'] as num?)?.toInt() ?? 0,
      balanceRial: (family['balance'] as num?)?.toInt() ?? 0,
      members: parse('members', MemberExpense.fromJson),
      categories: parse('categories', CategoryExpense.fromJson),
      cards: parse('cards', CardExpense.fromJson),
    );
  }
}
