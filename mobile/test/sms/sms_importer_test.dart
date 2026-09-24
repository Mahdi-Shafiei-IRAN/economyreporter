import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  late FakeTransactionStore store;
  late SmsImporter importer;

  Future<void> allowBanks() async {
    await store.addAllowedSender('BankMellat');
    await store.addAllowedSender('ملی');
  }

  setUp(() async {
    store = FakeTransactionStore();
    importer = SmsImporter(store);
    await allowBanks();
  });

  test('فقط تراکنش‌های واقعیِ فرستنده‌های مجاز وارد می‌شوند', () async {
    final messages = [
      const RawSms(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
      ),
      const RawSms(sender: 'BankMellat', body: 'رمز پویا: 84512 اعتبار 60 ثانیه'),
      const RawSms(sender: 'Ad', body: 'فروش ویژه تخفیف!'),
      // مبلغ دارد ولی فرستنده بانک نیست — قبلاً اشتباهی هزینه ثبت می‌شد
      const RawSms(sender: 'Digikala', body: 'خرید مبلغ 990,000 ریال با کد تخفیف'),
      const RawSms(sender: 'ملی', body: 'واریز مبلغ 10,000,000 ریال به حساب 0101234567'),
    ];

    final result = await importer.importAll(messages);

    expect(result.created, 2);
    expect(result.skipped, 1); // OTP از فرستنده‌ی مجاز
    expect(result.notAllowed, 2); // تبلیغ + فروشگاهِ مبلغ‌دار
    expect(await store.getAll().then((l) => l.length), 2);
  });

  test('قانون: از فرستنده‌ی مجاز هم فقط پیامکِ دارای شماره‌ی حساب/کارت ثبت می‌شود',
      () async {
    await store.addAllowedSender('DigiPay');
    final result = await importer.importAll(const [
      // اعتبارِ کیف پول/وام: پولی در حسابِ بانکی جابه‌جا نشده
      RawSms(
          sender: 'DigiPay',
          body: 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: ۱۰۰٬۰۰۰٬۰۰۰ ریال'),
      RawSms(sender: 'DigiPay', body: 'بازگشت پول\nمبلغ 31,000 ریال به دیجی‌کارت شما واریز شد.'),
      // اطلاعیه‌ی کسرِ آینده، بی‌شماره
      RawSms(
          sender: 'BankMellat',
          body: 'بانک ملت\nبسته پیامکی تمدید و مبلغ 300,000 ریال کسر خواهد شد.'),
      // تراکنشِ واقعی
      RawSms(sender: 'BankMellat', body: 'حساب1000000001\nبرداشت12,345,000\nمانده6,000,000'),
    ]);
    expect(result.created, 1);
    expect(result.skipped, 3);
    expect((await store.getAll()).single.accountRef, '1000000001');
  });

  test('تا فرستنده‌ای مجاز نشده هیچ پیامکی ثبت نمی‌شود', () async {
    store = FakeTransactionStore();
    importer = SmsImporter(store);

    final result = await importer.importAll(const [
      RawSms(sender: 'BankMellat', body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234'),
    ]);
    expect(result.created, 0);
    expect(result.notAllowed, 1);
    expect(
      await importer.importOne(
          const RawSms(sender: 'BankMellat', body: 'خرید مبلغ 80,000 ریال از کارت 1234')),
      isNull,
    );
    expect(await store.getAll(), isEmpty);
  });

  test('سرشماره‌ی عددی با هر شکلِ نوشتن؛ بانک از خودِ فرستنده‌ی مجاز', () async {
    await store.addAllowedSender('+98200012345', bankId: 'tejarat');

    final imported = await importer.importOne(RawSms(
      sender: '0200012345',
      body: 'برداشت مبلغ 500,000 ریال از حساب 1234567',
      receivedAt: DateTime.utc(2026, 9, 1),
    ));

    expect(imported, isNotNull);
    final saved = await store.getById(imported!.id);
    expect(saved!.bankId, 'tejarat');
    expect(saved.smsSender, '0200012345');
  });

  test('پیامک تکراری دوباره ذخیره نمی‌شود', () async {
    final at = DateTime.utc(2026, 6, 1, 10, 0);
    final sms = RawSms(
      sender: 'BankMellat',
      body: 'برداشت مبلغ 500,000 ریال از کارت 1234',
      receivedAt: at,
    );
    expect(await importer.importOne(sms), isNotNull);
    expect(await importer.importOne(sms), isNull); // تکراری
    expect(await store.getAll().then((l) => l.length), 1);
  });

  group('نوتیفیکیشن دسته‌بندی', () {
    RawSms sms(DateTime at, {String card = '1234'}) => RawSms(
          sender: 'BankMellat',
          body: 'خرید مبلغ 80,000 ریال از کارت $card',
          receivedAt: at,
        );

    test('تراکنش‌های قبل از «شروع دسته‌بندی» نوتیفیکیشن ندارند', () async {
      store = FakeTransactionStore(categorizeFrom: DateTime.utc(2026, 9, 22, 20, 30));
      importer = SmsImporter(store);
      await allowBanks();

      final before = await importer.importOne(sms(DateTime.utc(2026, 9, 10)));
      final after = await importer.importOne(sms(DateTime.utc(2026, 9, 25)));
      expect(before!.promptCategorize, isFalse);
      expect(after!.promptCategorize, isTrue);
    });

    test('تراکنش کارتِ عضو دیگر روی گوشی من نوتیفیکیشن ندارد', () async {
      store.settings[SettingKeys.meUserId] = 'u-me';
      await store.addWallet(const Wallet(
        id: '',
        ownerName: 'بابا',
        ownerUserId: 'u-father',
        label: 'کارت حقوق',
        cardLast4: '1234',
      ));

      final fathers = await importer.importOne(sms(DateTime.utc(2026, 9, 25)));
      final mine = await importer.importOne(
          sms(DateTime.utc(2026, 9, 25, 1), card: '9999'));
      expect(fathers!.promptCategorize, isFalse);
      expect(mine!.promptCategorize, isTrue);
    });
  });

  test('رمزِ انتقالِ سپه (رمز: … اعتبار …) تراکنش نیست؛ حتی از فرستنده‌ی مجاز', () async {
    await store.addAllowedSender('+989100000000', bankId: 'sepah');
    final result = await importer.importAll(const [
      RawSms(
        sender: '+989100000000',
        body: 'بانک سپه\n 502229*5524  انتقال\nمبلغ 1,000,000 ريال\nرمز: 928517\n'
            'اعتبار 22:10:05\nZwFQsa9kcO+',
      ),
      RawSms(
        sender: '+989100000000',
        body: 'بانک سپه\n 610433*9635  انتقال\nمبلغ 2,800,000 ريال\nرمز: 891630\n'
            'اعتبار 11:19:34\nZwFQsa9kcO+',
      ),
    ]);
    expect(result.created, 0);
    expect(result.skipped, 2);
  });
}
