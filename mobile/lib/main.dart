import 'package:flutter/material.dart';

import 'core/auth/auth_repository.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/network/api_client.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
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
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _Bootstrap(),
    );
  }
}

class _Services {
  final AuthController auth;
  final DashboardController dashboard;
  const _Services(this.auth, this.dashboard);
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<_Services> _future = _init();

  Future<_Services> _init() async {
    final tokenStore = SecureTokenStore();
    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenStore: tokenStore);
    final authRepo = AuthRepository(api, tokenStore);
    final auth = AuthController(authRepo);
    await auth.bootstrap();

    final db = await openAppDatabase();
    final dashboard = DashboardController(TransactionRepository(db));
    return _Services(auth, dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Services>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('خطا در راه‌اندازی:\n${snapshot.error}',
                    textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return _Root(services: snapshot.data!);
      },
    );
  }
}

/// بسته به وضعیت احراز هویت، ورود یا داشبورد را نشان می‌دهد.
class _Root extends StatelessWidget {
  final _Services services;

  const _Root({required this.services});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: services.auth,
      builder: (context, _) {
        if (services.auth.authenticated) {
          return DashboardScreen(
            controller: services.dashboard,
            onLogout: services.auth.logout,
          );
        }
        return LoginScreen(controller: services.auth);
      },
    );
  }
}
