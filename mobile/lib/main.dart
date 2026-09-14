import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/auth/auth_repository.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/dashboard/remote_dashboard_api.dart';
import 'core/database/app_database.dart';
import 'core/family/family_api.dart';
import 'core/network/api_client.dart';
import 'core/sms/sms_importer.dart';
import 'core/sync/remote_transaction_api.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/update_service.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/categories/categorize_screen.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/family/family_dashboard_screen.dart';
import 'features/notifications/notification_service.dart';
import 'features/senders/senders_screen.dart';
import 'features/sms/sms_inbox_service.dart';
import 'features/transactions/data/transaction_repository.dart';

/// کلید ناوبری سراسری (برای باز کردن صفحه از نوتیفیکیشن).
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  runApp(const EconomyApp());
}

class EconomyApp extends StatelessWidget {
  const EconomyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'مالی خانواده',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        themeMode: themeController.mode,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _Bootstrap(),
      ),
    );
  }
}

class _Services {
  final AuthController auth;
  final DashboardController dashboard;
  final SyncService sync;
  final ProfileService profile;
  final RemoteDashboardApi dashboardApi;
  final SmsInboxService smsInbox;
  final UpdateService updater;

  const _Services({
    required this.auth,
    required this.dashboard,
    required this.sync,
    required this.profile,
    required this.dashboardApi,
    required this.smsInbox,
    required this.updater,
  });

  /// پروفایل/اعضا از سرور → ارسال و دریافت تراکنش‌ها → تازه‌سازی صفحه.
  /// در حالت آفلاین بی‌صدا شکست می‌خورد (چیزی گم نمی‌شود).
  Future<SyncSummary> refreshFromServer({bool force = false}) async {
    if (await profile.refresh() == ProfileStatus.needsRelogin) {
      await auth.expireSession(kLegacyAccountNotice);
      return const SyncSummary(synced: 0, failed: 0, error: 'auth');
    }
    final summary = await sync.sync(force: force);
    await dashboard.load();
    return summary;
  }
}

/// پیام صفحه‌ی ورود وقتی گوشی هنوز با حسابِ قدیمیِ ایمیلی (مثل «کاربر تست») وارد است.
const kLegacyAccountNotice = 'ورود حالا با شماره موبایل است. با شماره و رمزی که مدیر '
    'خانواده در پنل مدیریت برایت ساخته وارد شو.';

/// پیام صفحه‌ی ورود وقتی سرور نشست را نمی‌پذیرد (کاربر حذف/غیرفعال شده).
const kSessionExpiredNotice =
    'حسابت روی سرور دیگر فعال نیست یا نشست تمام شده؛ دوباره وارد شو.';

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
    // کاربر در پنل حذف/غیرفعال شد یا نشست باطل است → برگشت به صفحه‌ی ورود.
    api.onSessionExpired = () => auth.expireSession(kSessionExpiredNotice);
    await auth.bootstrap();

    final db = await openAppDatabase();
    final repo = TransactionRepository(db);

    // شناسه‌ی ثابت گوشی (قبلاً هر اجرا یک شناسه‌ی تازه ساخته می‌شد).
    var deviceId = await repo.getSetting(SettingKeys.deviceId);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await repo.setSetting(SettingKeys.deviceId, deviceId);
    }

    final dashboard = DashboardController(repo, familyApi: DioFamilyApi(api.dio));
    final sync = SyncService(
      db: db,
      api: DioRemoteTransactionApi(api.dio),
      deviceId: deviceId,
    );
    final profile = ProfileService(DioFamilyApi(api.dio), repo);

    // هر ویرایش محلی (دسته‌بندی، حذف، کارت) بی‌درنگ برای بقیه‌ی اعضا فرستاده شود.
    dashboard.onLocalChange = () => sync.sync().ignore();

    final smsInbox = SmsInboxService(
      importer: SmsImporter(repo, deviceId: deviceId),
      onChanged: () {
        dashboard.load(); // تازه‌سازی صفحه
        sync.sync().ignore(); // ارسال خودکار به سرور خانواده
      },
      onTransactionCaptured: (tx) {
        if (tx.promptCategorize) {
          NotificationService.showTransaction(tx.id, tx.amountRial);
        }
      },
    );

    // پیشنهاد فرستنده‌های بانک از صندوق گوشی؛ و بعد از مجاز کردن یک فرستنده،
    // خواندن دوباره‌ی صندوق تا پیامک‌های قبلیِ همان فرستنده هم ثبت شوند.
    dashboard
      ..readInbox = smsInbox.readInbox
      ..onSendersChanged = smsInbox.importInbox;

    return _Services(
      auth: auth,
      dashboard: dashboard,
      sync: sync,
      profile: profile,
      dashboardApi: DioRemoteDashboardApi(api.dio),
      smsInbox: smsInbox,
      updater: UpdateService(AppConfig.updatesBaseUrl),
    );
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

/// بسته به وضعیت احراز هویت، ورود یا صفحه‌ی اصلی را نشان می‌دهد.
class _Root extends StatefulWidget {
  final _Services services;

  const _Root({required this.services});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  bool _setupDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.auth.addListener(_maybeSetup);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSetup());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.services.auth.removeListener(_maybeSetup);
    super.dispose();
  }

  /// برگشت به اپ: پیامک‌هایی که در پس‌زمینه ذخیره شده‌اند و تغییرات بقیه‌ی اعضا.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final s = widget.services;
    s.dashboard.load();
    if (s.auth.authenticated) s.refreshFromServer().ignore();
  }

  /// بعد از ورود: پروفایل و sync، نوتیفیکیشن، مجوز پیامک، وارد کردن صندوق و
  /// گوش‌دادن زنده؛ و اگر اپ از نوتیفیکیشن باز شده، رفتن به دسته‌بندی.
  Future<void> _maybeSetup() async {
    final s = widget.services;
    if (!s.auth.authenticated) {
      // خروج (دستی یا اجباری): با ورود بعدی دوباره راه‌اندازی شود.
      _setupDone = false;
      return;
    }
    if (_setupDone) return;
    _setupDone = true;

    s.refreshFromServer().ignore();
    await NotificationService.init(onTap: _openCategorize);

    final granted = await s.smsInbox.requestPermission();
    if (granted) {
      await s.smsInbox.importInbox();
      await s.dashboard.load();
      s.smsInbox.startListener();
    }

    final launchPayload = await NotificationService.launchPayload();
    if (launchPayload != null) {
      _openCategorize(launchPayload);
    } else if (granted && s.dashboard.needsSenderSetup) {
      // بعد از نصب/ورود: اگر هیچ فرستنده‌ای مجاز نشده، صفحه‌ی انتخاب فرستنده‌ها را
      // خودکار باز کن تا کاربر از روی پیامک‌هایش انتخاب و صاحب تعیین کند.
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => SendersScreen(controller: s.dashboard),
      ));
    }

    _checkForUpdate();
  }

  /// چک نسخه‌ی جدید از سرور و پیشنهاد به‌روزرسانی (بی‌صدا اگر آفلاین/نبود).
  Future<void> _checkForUpdate() async {
    final info = await widget.services.updater.check();
    if (info == null || !mounted) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final go = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text('نسخه‌ی جدید (${info.versionName}) آماده است'),
        content: Text(info.notes.isEmpty
            ? 'یک نسخه‌ی تازه‌ی برنامه روی سرور هست. همین حالا به‌روزرسانی کن.'
            : info.notes),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('بعداً'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('به‌روزرسانی'),
          ),
        ],
      ),
    );
    if (go == true) _runUpdate(info);
  }

  Future<void> _runUpdate(AppUpdateInfo info) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('در حال دانلود…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value == 0 ? null : value),
              const SizedBox(height: 8),
              Text('${(value * 100).round()}٪'),
            ],
          ),
        ),
      ),
    );
    try {
      await widget.services.updater
          .downloadAndInstall(info, onProgress: (p) => progress.value = p);
    } catch (_) {
      // دانلود/نصب نشد
    } finally {
      navigatorKey.currentState?.pop(); // بستن دیالوگ دانلود
    }
  }

  /// باز کردن صفحه‌ی دسته‌بندی برای تراکنشِ نوتیفیکیشن.
  Future<void> _openCategorize(String txId) async {
    final record = await widget.services.dashboard.transactionById(txId);
    if (record == null) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => CategorizeScreen(
          controller: widget.services.dashboard,
          record: record,
        ),
      ),
    );
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
            onLogout: () {
              _setupDone = false;
              services.auth.logout();
            },
            onSync: () async =>
                (await services.refreshFromServer(force: true)).message,
            onOpenFamilyDashboard: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FamilyDashboardScreen(
                  api: services.dashboardApi,
                  initialPeriod: services.dashboard.period,
                  now: services.dashboard.now,
                ),
              ),
            ),
          );
        }
        return LoginScreen(controller: services.auth);
      },
    );
  }
}
