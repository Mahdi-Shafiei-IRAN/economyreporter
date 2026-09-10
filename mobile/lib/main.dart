import 'package:flutter/material.dart';

import 'core/database/app_database.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/transactions/data/transaction_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EconomyApp());
}

class EconomyApp extends StatelessWidget {
  const EconomyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مدیریت مالی خانواده',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      // چیدمان راست‌به‌چپ برای کل اپ.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Bootstrap(),
    );
  }
}

/// باز کردن پایگاه‌داده و ساخت کنترلر، سپس نمایش داشبورد.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<DashboardController> _future = _init();

  Future<DashboardController> _init() async {
    final db = await openAppDatabase();
    return DashboardController(TransactionRepository(db));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'خطا در باز کردن پایگاه‌داده:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return DashboardScreen(controller: snapshot.data!);
      },
    );
  }
}
