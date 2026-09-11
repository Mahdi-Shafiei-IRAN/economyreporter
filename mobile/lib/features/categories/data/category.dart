/// مدل دسته و جمعِ هر دسته (برای گزارش).
library;

class Category {
  final String id;
  final String name;
  final bool isSystem;

  const Category({required this.id, required this.name, this.isSystem = false});

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as String,
        name: m['name'] as String,
        isSystem: (m['is_system'] as int? ?? 0) == 1,
      );
}

class CategoryTotal {
  final String categoryId;
  final String name;
  final int amountRial;

  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.amountRial,
  });
}
