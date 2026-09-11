import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/auth/auth_repository.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/dashboard/remote_dashboard_api.dart';
import 'core/database/app_database.dart';
import 'core/network/api_client.dart';
import 'core/sms/sms_importer.dart';
import 'core/sync/remote_transaction_api.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/family/family_dashboard_screen.dart';
import 'features/sms/sms_inbox_service.dart';
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
  final SyncService sync;
  final RemoteDashboardApi dashboardApi;
  final SmsInboxService smsInbox;
  const _Services(
    this.auth,
    this.dashboard,
    this.sync,
    this.dashboardApi,
    this.smsInbox,
  );
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
    final repo = TransactionRepository(db);
    final dashboard = DashboardController(repo);

    final sync = SyncService(
      db: db,
      api: DioRemoteTransactionApi(api.dio),
      deviceId: const Uuid().v4(),
    );
    final dashboardApi = DioRemoteDashboardApi(api.dio);

    final smsInbox = SmsInboxService(
      importer: SmsImporter(repo),
      onChanged: () {
        dashboard.load(); // تازه‌سازی داشبورد محلی
        sync.sync().ignore(); // ارسال خودکار به سرور (تا داشبورد خانواده هم به‌روز شود)
      },
    );

    // تلاش اولیه برای همگام‌سازی آنچه هنوز نرفته (در صورت آنلاین‌بودن).
    if (auth.authenticated) {
      sync.sync().ignore();
    }
    return _Services(auth, dashboard, sync, dashboardApi, smsInbox);
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
class _Root extends StatefulWidget {
  final _Services services;

  const _Root({required this.services});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _smsSetupDone = false;

  @override
  void initState() {
    super.initState();
    widget.services.auth.addListener(_maybeSetupSms);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSetupSms());
  }

  @override
  void dispose() {
    widget.services.auth.removeListener(_maybeSetupSms);
    super.dispose();
  }

  /// بعد از ورود، یک‌بار مجوز پیامک را می‌گیرد، صندوق را وارد و listener را شروع می‌کند.
  Future<void> _maybeSetupSms() async {
    if (_smsSetupDone || !widget.services.auth.authenticated) return;
    _smsSetupDone = true;
    final sms = widget.services.smsInbox;
    final granted = await sms.requestPermission();
    if (!granted) return;
    await sms.importInbox();
    sms.startListener();
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return AnimatedBuilder(
      animation: services.auth,
      builder: (context, _) {
        if (services.auth.authenticated) {
          return DashboardScreen(
            controller: services.dashboard,
            onLogout: services.auth.logout,
            onSync: () async {
              final s = await services.sync.sync();
              return 'همگام‌سازی: ${s.synced} موفق، ${s.failed} ناموفق';
            },
            onOpenFamilyDashboard: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    FamilyDashboardScreen(api: services.dashboardApi),
              ),
            ),
          );
        }
        return LoginScreen(controller: services.auth);
      },
    );
  }
}
