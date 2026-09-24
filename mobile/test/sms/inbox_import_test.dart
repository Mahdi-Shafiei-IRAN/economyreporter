import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

/// مشکلِ واقعی (کاربرِ دوم): بعد از مجاز کردنِ بانک فقط ۳۰۰ پیامکِ آخرِ **کلِ صندوق**
/// خوانده می‌شد؛ پیامک‌های قدیمی‌ترِ همان بانک هیچ‌وقت ثبت نمی‌شد، و برداشتن/افزودنِ
/// دوباره‌ی فرستنده هم چیزی را عوض نمی‌کرد.
void main() {
  final now = DateTime.utc(2026, 9, 24, 12);
  late FakeTransactionStore store;
  late SmsImporter importer;

  // ۱۰ پیامکِ ملت (قدیمی) + ۴۰۰ پیامکِ عادیِ جدیدتر (جدیدترین اول، مثلِ صندوق).
  final bank = [
    for (var i = 0; i < 10; i++)
      RawSms(
        sender: 'Bank Mellat',
        body: 'حساب4933787334\nبرداشت${(i + 1) * 1000}\nمانده${900000 - i * 1000}',
        receivedAt: now.subtract(Duration(days: 60 - i)),
      ),
  ];
  final chatter = [
    for (var i = 0; i < 400; i++)
      RawSms(sender: '+98912000${1000 + i}', body: 'سلام $i', receivedAt: now.subtract(Duration(minutes: i))),
  ];
  final inbox = [...chatter, ...bank.reversed];

  setUp(() {
    store = FakeTransactionStore(clock: () => now);
    importer = SmsImporter(store);
  });

  test('بارِ اول (یا full) کلِ صندوق خوانده می‌شود، نه ۳۰۰ تای آخر', () async {
    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    final r = await importer.importInbox(inbox);
    expect(r.created, 10);
  });

  test('بازشدنِ عادی فقط از آخرین خواندن؛ مجاز کردنِ بعدی (full) قدیمی‌ها را هم می‌آورد',
      () async {
    // اپ باز شد، هنوز هیچ فرستنده‌ای مجاز نیست → چیزی ثبت نمی‌شود ولی «آخرین خواندن» ثبت می‌شود.
    expect((await importer.importInbox(inbox)).created, 0);

    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    // بازشدنِ بعدی: پیامک‌های ۶۰ روزِ پیش خارج از پنجره‌اند.
    expect((await importer.importInbox(inbox)).created, 0);
    // همان کاری که بعد از «مجاز کن» / «خواندنِ دوباره» انجام می‌شود.
    expect((await importer.importInbox(inbox, full: true)).created, 10);
    // تکرار چیزی را دوباره ثبت نمی‌کند.
    expect((await importer.importInbox(inbox, full: true)).created, 0);
  });

  test('پیامکِ تازه بعد از آخرین خواندن ثبت می‌شود', () async {
    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    await importer.importInbox(inbox);
    final fresh = RawSms(
        sender: 'Bank Mellat',
        body: 'حساب4933787334\nواریز485\nمانده1,040,190',
        receivedAt: now.add(const Duration(hours: 1)));
    expect((await importer.importInbox([fresh, ...inbox])).created, 1);
  });

  group('DashboardController', () {
    late DashboardController c;

    setUp(() async {
      c = DashboardController(store, clock: () => now)
        ..readInbox = (() async => inbox)
        ..importWholeInbox =
            (() async => (await importer.importInbox(inbox, full: true)).created);
      c.onSendersChanged = c.importWholeInbox;
      await importer.importInbox(inbox); // بازشدنِ اپ پیش از مجاز کردن
      await c.load();
    });

    test('مجاز کردنِ فرستنده همه‌ی پیامک‌های قدیمی‌ترش را ثبت می‌کند', () async {
      await c.addAllowedSender('Bank Mellat', bankId: 'mellat');
      expect(c.itemsIn(const Period.all()), hasLength(10));
      expect(c.transactionsOfSender('Bank Mellat'), hasLength(10));
    });

    test('برداشتن با حذفِ تراکنش‌ها، و افزودنِ دوباره دوباره‌خوانی نمی‌کند اگر حذف شده باشند',
        () async {
      await c.addAllowedSender('Bank Mellat', bankId: 'mellat');
      await c.removeAllowedSender(c.allowedSenders.single.id, deleteTransactions: true);
      expect(c.itemsIn(const Period.all()), isEmpty);
      expect(c.allowedSenders, isEmpty);
    });

    test('«خواندنِ دوباره‌ی همه‌ی پیامک‌ها»', () async {
      await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
      expect(await c.rescanInbox(), 10);
      expect(await c.rescanInbox(), 0);
    });
  });
}
