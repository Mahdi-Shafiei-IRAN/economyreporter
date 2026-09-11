/// تم اپ: آبیِ «اعتماد» برای برند، سبز/قرمز معنایی برای درآمد/هزینه، فونت Vazirmatn.
/// رنگ‌ها فقط از این‌جا و از Theme.of(context) خوانده شوند (نه hex در صفحه‌ها).
library;

import 'package:flutter/material.dart';

const String kAppFontFamily = 'Vazirmatn';
const Color _brandBlue = Color(0xFF1E40AF);

/// رنگ‌های معنایی مالی (در تم روشن و تیره جدا تنظیم شده‌اند تا کنتراست بماند).
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  final Color income;
  final Color incomeContainer;
  final Color expense;
  final Color expenseContainer;
  final Color transfer;
  final Color transferContainer;
  final Color warning;
  final Color warningContainer;

  /// دو سرِ گرادیان کارت خلاصه (متن رویش سفید است).
  final Color heroStart;
  final Color heroEnd;

  const FinanceColors({
    required this.income,
    required this.incomeContainer,
    required this.expense,
    required this.expenseContainer,
    required this.transfer,
    required this.transferContainer,
    required this.warning,
    required this.warningContainer,
    required this.heroStart,
    required this.heroEnd,
  });

  static const light = FinanceColors(
    income: Color(0xFF047857),
    incomeContainer: Color(0xFFD1FAE5),
    expense: Color(0xFFB91C1C),
    expenseContainer: Color(0xFFFEE2E2),
    transfer: Color(0xFF475569),
    transferContainer: Color(0xFFE2E8F0),
    warning: Color(0xFF92400E),
    warningContainer: Color(0xFFFEF3C7),
    heroStart: Color(0xFF1E40AF),
    heroEnd: Color(0xFF1E3A8A),
  );

  static const dark = FinanceColors(
    income: Color(0xFF34D399),
    incomeContainer: Color(0xFF064E3B),
    expense: Color(0xFFF87171),
    expenseContainer: Color(0xFF7F1D1D),
    transfer: Color(0xFFCBD5E1),
    transferContainer: Color(0xFF334155),
    warning: Color(0xFFFCD34D),
    warningContainer: Color(0xFF78350F),
    heroStart: Color(0xFF1E3A8A),
    heroEnd: Color(0xFF172554),
  );

  static FinanceColors of(BuildContext context) =>
      Theme.of(context).extension<FinanceColors>() ?? light;

  @override
  FinanceColors copyWith({
    Color? income,
    Color? incomeContainer,
    Color? expense,
    Color? expenseContainer,
    Color? transfer,
    Color? transferContainer,
    Color? warning,
    Color? warningContainer,
    Color? heroStart,
    Color? heroEnd,
  }) =>
      FinanceColors(
        income: income ?? this.income,
        incomeContainer: incomeContainer ?? this.incomeContainer,
        expense: expense ?? this.expense,
        expenseContainer: expenseContainer ?? this.expenseContainer,
        transfer: transfer ?? this.transfer,
        transferContainer: transferContainer ?? this.transferContainer,
        warning: warning ?? this.warning,
        warningContainer: warningContainer ?? this.warningContainer,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
      );

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseContainer: Color.lerp(expenseContainer, other.expenseContainer, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      transferContainer: Color.lerp(transferContainer, other.transferContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
    );
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(seedColor: _brandBlue, brightness: brightness);
  final scheme = isDark
      ? seeded.copyWith(
          surface: const Color(0xFF0F172A),
          surfaceContainerLowest: const Color(0xFF0B1222),
          surfaceContainerLow: const Color(0xFF151F36),
          surfaceContainer: const Color(0xFF1A2540),
          surfaceContainerHigh: const Color(0xFF212D4B),
          surfaceContainerHighest: const Color(0xFF293657),
        )
      : seeded.copyWith(
          primary: _brandBlue,
          surface: const Color(0xFFF4F6FA),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: const Color(0xFFEDF0F6),
          surfaceContainerHigh: const Color(0xFFE5E9F1),
          surfaceContainerHighest: const Color(0xFFDCE2EC),
        );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kAppFontFamily,
  );
  final outline = scheme.outlineVariant.withOpacity(isDark ? 0.35 : 0.7);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    extensions: [isDark ? FinanceColors.dark : FinanceColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontFamily: kAppFontFamily,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardTheme(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(space: 1, thickness: 1, color: outline),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        base.textTheme.labelMedium?.copyWith(fontFamily: kAppFontFamily),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: BorderSide(color: outline)),
      labelStyle: base.textTheme.labelLarge?.copyWith(fontFamily: kAppFontFamily),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
