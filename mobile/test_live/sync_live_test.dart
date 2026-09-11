/// تست زنده‌ی همگام‌سازی با سرور واقعی Django (HTTP واقعی + JWT)، با دو «گوشی»:
/// من و بابا. جزو تست‌های عادی نیست.
///
/// اجرا: یک سرور آزمایشی با دیتابیس جدا، و دو کاربر در یک خانواده با رمز Live@12345:
/// 09120000001 («مهدی») و 09120000002 («بابا») — روش ساختنشان در docs/run-on-phone.md.
///   LIVE_API=http://127.0.0.1:8001/api/v1 flutter test test_live
library;

import 'dart:io';

import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/network/api_client.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sync/remote_transaction_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../test/helpers/db_test_helper.dart';
import '../test/helpers/in_memory_token_store.dart';

class _Phone {
  final TransactionRepository repo;
  final SyncService sync;
  final ProfileService profile;
  final SmsImporter importer;

  _Phone(this.repo, this.sync, this.profile, this.importer);

  static Future<_Phone> login(String base, String phone, String deviceId) async {
    final tokens = InMemoryTokenStore();
    final api = ApiClient(baseUrl: base, tokenStore: tokens);
    await AuthRepository(api, tokens).login(phone: phone, password: 'Live@12345');
    // هر «گوشی» دیتابیس جدای خودش را دارد.
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final repo = TransactionRepository(db);
    return _Phone(
      repo,
      SyncService(db: db, api: DioRemoteTransactionApi(api.dio), deviceId: deviceId),
      ProfileService(DioFamilyApi(api.dio), repo),
      SmsImporter(repo, deviceId: deviceId),
    );
  }
}

void main() {
  final base = Platform.environment['LIVE_API'];
  setUpAll(initSqfliteFfiForTests);

  test('دو گوشی: ارسال بدون خطا، دریافت، صاحب کارت، ویرایش فقط توسط صاحب', () async {
    // شماره به هر شکلی (+98 / ارقام فارسی) وارد شود، سرور همان کاربر را می‌شناسد.
    final me = await _Phone.login(base!, '+989120000001', 'phone-me');
    final father = await _Phone.login(base, '۰۹۱۲۰۰۰۰۰۰۲', 'phone-father');
    expect(await me.profile.refresh(), ProfileStatus.ok);
    expect(await father.profile.refresh(), ProfileStatus.ok);
    final fatherId = await father.repo.getSetting(SettingKeys.meUserId);
    final meId = await me.repo.getSetting(SettingKeys.meUserId);
    expect(await me.repo.getSetting(SettingKeys.meName), 'مهدی');

    // روی گوشی من: کارت 1234 مال باباست (عضو اپ).
    await me.repo.addWallet(Wallet(
      id: '',
      ownerName: 'بابا',
      ownerUserId: fatherId,
      label: 'کارت حقوق',
      cardLast4: '1234',
    ));
    // فقط پیامک فرستنده‌های مجاز ثبت می‌شود.
    await me.repo.addAllowedSender('BankMellat', bankId: 'mellat');

    // پیامک‌های بدون «طرف حساب» (همان حالتی که قبلاً ۱۰۷ خطای sync می‌داد).
    // مبلغ و زمان در هر اجرا یکتاست تا دیتابیسِ سرورِ آزمایشی تکراری نبیند.
    final now = DateTime.now().toUtc();
    final n = now.millisecondsSinceEpoch % 900 + 100;
    final a = await me.importer.importOne(RawSms(
      sender: 'BankMellat',
      body: 'خرید مبلغ $n,000 ریال از کارت 1234 مانده 5,000,000 ریال',
      receivedAt: now,
    ));
    final b = await me.importer.importOne(RawSms(
      sender: 'BankMellat',
      body: 'خرید مبلغ $n,500 ریال از کارت 9999',
      receivedAt: now,
    ));
    // پیامکِ مبلغ‌دارِ فروشگاه (فرستنده‌ی غیرمجاز) ثبت نمی‌شود.
    final ad = await me.importer.importOne(RawSms(
      sender: 'Digikala',
      body: 'خرید مبلغ $n,900 ریال با کد تخفیف',
      receivedAt: now,
    ));
    expect(a, isNotNull);
    expect(b, isNotNull);
    expect(ad, isNull);

    final push = await me.sync.sync(force: true);
    expect(push.error, isNull);
    expect(push.failed, 0);
    expect(push.synced, 2);

    // گوشی بابا هر دو را دریافت می‌کند؛ فقط کارت 1234 مال خودش است.
    final pull = await father.sync.sync(force: true);
    expect(pull.pulled, greaterThanOrEqualTo(2));
    final fathersTx = (await father.repo.getById(a!.id))!;
    final myTx = (await father.repo.getById(b!.id))!;
    expect(fathersTx.ownerUserId, fatherId);
    expect(fathersTx.ownerName, 'بابا');
    expect(fathersTx.walletLabel, 'کارت حقوق');
    expect(myTx.ownerUserId, meId);
    expect(fathersTx.smsBody, isNull); // متن پیامک هرگز از سرور نمی‌آید

    // بابا تراکنش خودش را دسته‌بندی می‌کند → به گوشی من می‌رسد.
    final fruit = (await father.repo.categories()).firstWhere((c) => c.name == 'میوه');
    await father.repo.categorize(fathersTx.id, [fruit.id], description: 'میوه‌فروشی');
    expect((await father.sync.sync(force: true)).synced, 1);

    await me.sync.sync(force: true);
    final onMe = await me.repo.getById(fathersTx.id);
    expect(onMe!.allocations.single.categoryName, 'میوه');
    expect(onMe.description, 'میوه‌فروشی');
    expect(onMe.smsBody, isNotNull); // متن پیامک روی گوشیِ دریافت‌کننده ماند

    // اگر گوشی بابا تراکنشِ من را عوض کند، سرور رد می‌کند و نسخه‌ی سرور برمی‌گردد.
    await father.repo.updateTransaction(myTx.id, description: 'دست بابا');
    final rejected = await father.sync.sync(force: true);
    expect(rejected.rejected, 1);
    expect((await father.repo.getById(myTx.id))!.description, isNot('دست بابا'));

    // بابا تراکنشش را «نامعتبر» می‌کند → روی گوشی من هم پنهان می‌شود.
    await father.repo.deleteTransaction(fathersTx.id);
    await father.sync.sync(force: true);
    await me.sync.sync(force: true);
    expect((await me.repo.getAll()).map((t) => t.id), isNot(contains(fathersTx.id)));
  }, skip: base == null ? 'LIVE_API تنظیم نشده' : false);

  test('همان گوشی با حساب خانواده‌ی دیگر: تراکنش‌های پیامکِ گوشی به خانواده‌ی جدید می‌رود',
      () async {
    final tokens = InMemoryTokenStore();
    final api = ApiClient(baseUrl: base!, tokenStore: tokens);
    final auth = AuthRepository(api, tokens);
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final repo = TransactionRepository(db);
    final remoteApi = DioRemoteTransactionApi(api.dio);
    final sync = SyncService(db: db, api: remoteApi, deviceId: 'phone-switch');
    final profile = ProfileService(DioFamilyApi(api.dio), repo);

    // ۱) حساب قدیمی (مثل «کاربر تست»): پیامک ثبت و به خانواده‌ی قدیمی فرستاده می‌شود.
    await auth.login(phone: '09120000003', password: 'Live@12345');
    expect(await profile.refresh(), ProfileStatus.ok);
    await repo.addAllowedSender('BankMellat', bankId: 'mellat');
    final now = DateTime.now().toUtc();
    final n = now.millisecondsSinceEpoch % 900 + 100;
    final captured = await SmsImporter(repo).importOne(RawSms(
      sender: 'BankMellat',
      body: 'خرید مبلغ $n,300 ریال',
      receivedAt: now,
    ));
    expect((await sync.sync(force: true)).synced, 1);

    // ۲) خروج و ورود با حساب واقعی (خانواده‌ی دیگر) روی همان گوشی.
    await auth.logout();
    await auth.login(phone: '09120000004', password: 'Live@12345');
    expect(await profile.refresh(), ProfileStatus.ok);
    final moved = (await repo.getAll()).single;
    expect(moved.id, isNot(captured!.id));
    expect(moved.ownerUserId, await repo.getSetting(SettingKeys.meUserId));
    expect(await repo.getSetting(SettingKeys.meName), 'جدید');

    // قبلاً این‌جا «تعارض شناسه» می‌گرفت و هیچ‌وقت به خانواده‌ی جدید نمی‌رسید.
    final push = await sync.sync(force: true);
    expect(push.failed, 0);
    expect(push.synced, 1);
    final page = await remoteApi.pull();
    expect(page.results.map((r) => r['id']), contains(moved.id));
  }, skip: base == null ? 'LIVE_API تنظیم نشده' : false);

  test('سرور در دسترس نیست → تراکنش در صف می‌ماند و پیام روشن است', () async {
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final repo = TransactionRepository(db);
    await repo.addAllowedSender('BankMellat');
    final api = ApiClient(baseUrl: 'http://127.0.0.1:9/api/v1', tokenStore: InMemoryTokenStore());
    final sync = SyncService(db: db, api: DioRemoteTransactionApi(api.dio), deviceId: 'x');
    await SmsImporter(repo).importOne(const RawSms(
      sender: 'BankMellat',
      body: 'خرید مبلغ 50,000 ریال از کارت 9999',
    ));

    final s = await sync.sync(force: true);
    expect(s.offline, isTrue);
    expect(s.message, contains('سرور در دسترس نبود'));
    expect(await repo.pendingSyncCount(), 1);
  }, skip: base == null ? 'LIVE_API تنظیم نشده' : false);
}
