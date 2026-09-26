import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/auth/auth_repository.dart';
import 'core/auth/token_store.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/family/family_api.dart';
import 'core/family/health_api.dart';
import 'core/format/money_format.dart';
import 'core/ledger/ledger_repository.dart';
import 'core/ledger/ledger_sync.dart';
import 'core/network/api_client.dart';
import 'core/store/app_store.dart';
import 'core/sync/remote_sync_api.dart';
import 'core/sync/sync_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/update_service.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/family/add_member_screen.dart';
import 'features/ledger/ledger_controller.dart';
import 'features/ledger/ledger_health.dart';
import 'features/ledger/ledger_home_screen.dart';
import 'features/ledger/ledger_notifications.dart';
import 'features/ledger/ledger_settings_screen.dart';
import 'features/ledger/pending_screen.dart';
import 'features/ledger/sender_ops.dart';
import 'features/notifications/notification_service.dart';
import 'features/sms/sms_inbox_service.dart';

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
  final AppStore store; // تنظیمات، فرستنده‌ها، کیف‌ها و بودجه
  final SyncService sync; // کیف‌ها و بودجه با سرور
  final ProfileService profile;
  final FamilyApi familyApi;
  final HealthApi healthApi;
  final SmsInboxService smsInbox;
  final UpdateService updater;
  final LedgerController ledger;
  final LedgerSyncService ledgerSync;
  final String deviceId;
  String? appVersion;

  _Services({
    required this.auth,
    required this.store,
    required this.sync,
    required this.profile,
    required this.familyApi,
    required this.healthApi,
    required this.smsInbox,
    required this.updater,
    required this.ledger,
    required this.ledgerSync,
    required this.deviceId,
  });

  /// پروفایل/اعضا از سرور → کیف‌ها و بودجه → دفتر. در حالت آفلاین بی‌صدا شکست می‌خورد (چیزی گم نمی‌شود).
  Future<void> refreshFromServer() async {
    final previousUser = await store.getSetting(SettingKeys.meUserId);
    if (await profile.refresh() == ProfileStatus.needsRelogin) {
      await auth.expireSession(kLegacyAccountNotice);
      return;
    }
    final currentUser = await store.getSetting(SettingKeys.meUserId);
    if (previousUser != null && currentUser != null && previousUser != currentUser) {
      // کاربرِ دیگری روی همین گوشی وارد شد: دفترِ قبلی به نامِ او فرستاده نشود (طرح ۱۲.۸).
      await ledger.repo.resetForAccountSwitch();
    }
    await sync.sync().catchError((_) => SyncSummary.ok);
    await syncLedger();
  }

  Future<LedgerSyncResult> syncLedger() async {
    final startBefore = await ledger.repo.startDate();
    final result = await ledgerSync.sync();
    if (await ledger.repo.startDate() != startBefore) {
      // نصبِ دوباره: تاریخِ شروعِ اصلی از سرور آمد؛ پیامک‌های قبل از آن هم از صندوق خوانده شوند.
      await ledger.syncInbox().catchError((_) => 0);
    } else {
      await ledger.load();
    }
    return result;
  }

  /// «همگام‌سازی الان» در تنظیمات.
  Future<String> syncLedgerNow() async {
    await sync.sync().catchError((_) => SyncSummary.ok);
    final r = await syncLedger();
    if (r.error != null) return 'همگام‌سازی نشد: ${r.error}. تغییرها روی گوشی می‌مانند و بعداً فرستاده می‌شوند.';
    return 'همگام‌سازی انجام شد: ${toPersianDigits('${r.sent}')} ارسال، ${toPersianDigits('${r.received}')} دریافت'
        '${r.failed > 0 ? '، ${toPersianDigits('${r.failed}')} ناموفق' : ''}';
  }

  Future<void> reportHealth({bool force = false}) async {
    appVersion ??= await updater.currentVersionName();
    await reportLedgerHealthIfDue(ledger,
        api: healthApi, deviceId: deviceId, appVersion: appVersion, force: force);
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
    final store = AppStore(db);

    // شناسه‌ی ثابت گوشی.
    var deviceId = await store.getSetting(SettingKeys.deviceId);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await store.setSetting(SettingKeys.deviceId, deviceId);
    }

    final sync = SyncService(store: store, api: DioRemoteSyncApi(api.dio));
    final familyApi = DioFamilyApi(api.dio);
    final ledgerRepo = LedgerRepository(db, deviceId: deviceId);

    late final SmsInboxService smsInbox;
    final ledger = LedgerController(
      ledgerRepo,
      allowedSenders: store.allowedSenders,
      readInbox: () async => [for (final raw in await smsInbox.readInbox()) toIncomingSms(raw)],
      senders: ledgerSenderOps(
        store,
        readInbox: () => smsInbox.readInbox(limit: 5000),
        me: () async {
          final p = await ledgerRepo.people();
          return (meName: p.meName, meUserId: p.meUserId);
        },
      ),
    );
    smsInbox = SmsInboxService(
      onLiveSms: (raw) async {
        for (final item in await ledger.intake([toIncomingSms(raw)])) {
          await NotificationService.showLedgerSms(item, ledger.account(item.suggestion.accountId));
        }
      },
    );

    // نسخه‌ی ۲ همیشه روشن (طرح ۱۲.۸): گوشی‌ای که هنوز روشنش نکرده بود راهنمای سه‌قدمی را می‌بیند.
    if (!await ledgerRepo.isEnabled()) {
      await ledgerRepo.setEnabled(true);
      await ledgerRepo.ensureStartDate();
    }
    await ledger.load();

    // هر تغییرِ دفتر: چند ثانیه بعد (تا چند تغییرِ پشتِ هم یک‌جا بروند) به سرور.
    final ledgerSync = LedgerSyncService(ledgerRepo, DioLedgerRemote(api.dio));
    Timer? debounce;
    ledger.onLocalChange = () {
      debounce?.cancel();
      debounce = Timer(const Duration(seconds: 3), () async {
        if (!auth.authenticated) return;
        await sync.sync().catchError((_) => SyncSummary.ok);
        await ledgerSync.sync();
        await ledger.load();
      });
    };

    return _Services(
      auth: auth,
      store: store,
      sync: sync,
      profile: ProfileService(familyApi, store),
      familyApi: familyApi,
      healthApi: DioHealthApi(api.dio),
      smsInbox: smsInbox,
      updater: UpdateService(AppConfig.updatesBaseUrl),
      ledger: ledger,
      ledgerSync: ledgerSync,
      deviceId: deviceId,
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
                child: Text('خطا در راه‌اندازی:\n${snapshot.error}', textAlign: TextAlign.center),
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

  /// برگشت به اپ: پیامک‌ها و دکمه‌های نوتیفیکیشن که در پس‌زمینه ثبت شده‌اند، و سرور.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final s = widget.services;
    s.ledger.syncInbox().catchError((_) => 0).ignore();
    if (s.auth.authenticated) {
      s.refreshFromServer().ignore();
      s.reportHealth().ignore();
    }
  }

  /// بعد از ورود: سرور، نوتیفیکیشن، مجوز و خواندنِ پیامک، گوش‌دادنِ زنده و سلامت.
  Future<void> _maybeSetup() async {
    final s = widget.services;
    if (!s.auth.authenticated) {
      _setupDone = false;
      return;
    }
    if (_setupDone) return;
    _setupDone = true;

    // چکِ به‌روزرسانی مستقل و زودهنگام؛ نباید به مجوز پیامک/صندوق وابسته باشد.
    _checkForUpdate();
    s.refreshFromServer().ignore();

    try {
      await NotificationService.init(onTap: _onNotificationTap, onAction: _onNotificationAction);
      if (await s.smsInbox.requestPermission()) {
        try {
          await s.ledger.syncInbox();
        } catch (_) {
          // با کشیدنِ خانه به پایین دوباره خوانده می‌شود.
        }
        s.smsInbox.startListener();
      }
      s.reportHealth().ignore();
      final launchPayload = await NotificationService.launchPayload();
      if (launchPayload != null) _onNotificationTap(launchPayload);
    } catch (_) {
      // خطای راه‌اندازی (مجوز/صندوق/نوتیف) نباید بقیه‌ی اپ را زمین بزند.
    }
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('بعداً')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('به‌روزرسانی')),
        ],
      ),
    );
    if (go == true) _runUpdate(info);
  }

  /// دانلود با نوارِ پیشرفت (و دکمه‌ی لغو)، بعد نصب‌کننده‌ی اندروید؛ در خطا پیامِ فارسی و «دوباره».
  Future<void> _runUpdate(AppUpdateInfo info) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final progress = ValueNotifier<double>(0);
    final cancel = CancelToken();
    BuildContext? dialogCtx;
    var dialogOpen = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) {
        dialogCtx = context;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('دانلودِ نسخه‌ی ${info.versionName}'),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: value == 0 ? null : value),
                  const SizedBox(height: 8),
                  Text(value == 0 ? 'در حال اتصال…' : '${toPersianDigits('${(value * 100).round()}')}٪'),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => cancel.cancel(), child: const Text('لغو'))],
          ),
        );
      },
    ).then((_) => dialogOpen = false);

    String? path;
    String? error;
    try {
      path = await widget.services.updater.downloadApk(info,
          onProgress: (p) => progress.value = p, cancelToken: cancel);
    } on DioException catch (e) {
      if (!CancelToken.isCancel(e)) error = describeUpdateError(e);
    } catch (e) {
      error = describeUpdateError(e);
    }
    // خطای خیلی سریع (پیش از اولین فریم): صبر تا دیالوگ ساخته شود و بعد بسته شود.
    if (dialogCtx == null) await WidgetsBinding.instance.endOfFrame;
    final d = dialogCtx;
    if (dialogOpen && d != null && d.mounted) Navigator.of(d).pop();

    if (path != null) {
      try {
        await widget.services.updater.install(path);
      } catch (e) {
        error = describeUpdateError(e);
      }
    }
    if (error != null) _showUpdateError(info, error);
  }

  void _showUpdateError(AppUpdateInfo info, String message) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline_rounded),
        title: const Text('به‌روزرسانی انجام نشد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            const Text('یا فایل را با مرورگر از این آدرس بگیر و نصب کن:'),
            SelectableText(info.url, textDirection: TextDirection.ltr),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('بستن')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('دوباره')),
        ],
      ),
    ).then((again) {
      if (again == true) _runUpdate(info);
    });
  }

  /// بررسی دستیِ به‌روزرسانی (از تنظیمات)؛ همیشه بازخورد می‌دهد.
  Future<String> _manualCheckUpdate() async {
    final updater = widget.services.updater;
    final currentName = await updater.currentVersionName();
    final info = await updater.fetch();
    if (info == null) return 'اتصال به سرور نشد؛ اینترنت را بررسی کن و بعداً دوباره بزن.';
    if (compareVersionNames(info.versionName, currentName) > 0) {
      _runUpdate(info);
      return 'نسخه‌ی جدید ${info.versionName} پیدا شد (نسخه‌ی فعلی: $currentName)؛ در حال دانلود…';
    }
    return 'به‌روزترین نسخه را داری (نسخه‌ی فعلی: $currentName).';
  }

  /// لمسِ نوتیفیکیشنِ پیامک → «منتظرِ تأیید».
  void _onNotificationTap(String payload) {
    if (ledgerKeyOf(payload) == null) return;
    final ledger = widget.services.ledger;
    ledger.load().whenComplete(() => navigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => PendingScreen(controller: ledger))));
  }

  /// دکمه‌ی «ثبت» / «تراکنش نیست» روی نوتیفیکیشن وقتی اپ باز است.
  void _onNotificationAction(String actionId, String payload) {
    final key = ledgerKeyOf(payload);
    if (key != null) widget.services.ledger.applyNotificationAction(actionId, key).ignore();
  }

  void _openSettings(BuildContext context) {
    final s = widget.services;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LedgerSettingsScreen(
        controller: s.ledger,
        onCheckUpdate: _manualCheckUpdate,
        onSync: s.syncLedgerNow,
        onAddMember: s.ledger.isManager
            ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddMemberScreen(
                      onAdd: ({required phone, required password, fullName}) async {
                        final err = await addFamilyMember(s.familyApi, s.store,
                            phone: phone, password: password, fullName: fullName);
                        await s.ledger.load();
                        return err;
                      },
                    )))
            : null,
        onOpenDevicesHealth: () async {
          s.appVersion ??= await s.updater.currentVersionName();
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LedgerDevicesHealthScreen(
              controller: s.ledger,
              api: s.healthApi,
              deviceId: s.deviceId,
              appVersion: s.appVersion,
            ),
          ));
        },
        onLogout: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          _setupDone = false;
          s.auth.logout();
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return AnimatedBuilder(
      animation: services.auth,
      builder: (context, _) => services.auth.authenticated
          ? LedgerHomeScreen(
              controller: services.ledger,
              onOpenSettings: () => _openSettings(context),
            )
          : LoginScreen(controller: services.auth),
    );
  }
}
