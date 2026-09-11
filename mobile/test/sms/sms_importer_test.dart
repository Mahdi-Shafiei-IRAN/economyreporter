import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  late FakeTransactionStore store;
  late SmsImporter importer;

  setUp(() {
    store = FakeTransactionStore();
    importer = SmsImporter(store);
  });

  test('فقط تراکنش‌های واقعی وارد می‌شوند؛ OTP و نامرتبط رد می‌شوند', () async {
    final messages = [
      const RawSms(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
      ),
      const RawSms(sender: 'BankMellat', body: 'رمز پویا: 84512 اعتبار 60 ثانیه'),
      const RawSms(sender: 'Ad', body: 'فروش ویژه تخفیف!'),
      const RawSms(
        sender: 'ملی',
        body: 'واریز مبلغ 10,000,000 ریال به حساب شما',
      ),
    ];

    final result = await importer.importAll(messages);

    expect(result.created, 2); // فقط دو تراکنش واقعی
    expect(result.skipped, 2); // OTP + تبلیغ
    expect(await store.getAll().then((l) => l.length), 2);
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
}
