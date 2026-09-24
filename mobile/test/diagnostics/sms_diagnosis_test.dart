import 'package:economy/core/diagnostics/sms_diagnosis.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

// نمونه‌های واقعی کاربر با شماره حساب و مبلغِ ساختگی (حریم خصوصی).
const _mellatSender = '9830001234';
const _mellatBody = 'حساب1000000009\nبرداشت1,250,000\nمانده8,750,000\n05/07/01-15:40';

const _digipaySender = 'DigiPay';
const _digipayBody =
    'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: ۵۰٬۰۰۰٬۰۰۰ ریال';

const _otpBody = 'رمز پویا: 123456 مبلغ 1,000,000 ریال';

final _t0 = DateTime.utc(2026, 9, 23, 12);

RawSms _sms(String sender, String body, int minute) =>
    RawSms(sender: sender, body: body, receivedAt: _t0.add(Duration(minutes: minute)));

Future<(FakeTransactionStore, SmsImporter)> _setup() async {
  final store = FakeTransactionStore(clock: () => _t0);
  await store.addAllowedSender(_mellatSender, bankId: 'mellat');
  await store.addAllowedSender(_digipaySender);
  return (store, SmsImporter(store));
}

Future<SmsDiagnosisReport> _diagnose(
    FakeTransactionStore store, List<RawSms> inbox) async {
  return diagnoseSms(
    inbox: inbox,
    stored: [...await store.getAll(), ...await store.deletedSmsTransactions()],
    allowed: await store.allowedSenders(),
  );
}

void main() {
  test('پیامکِ ملت: شمرده شده و قانونِ پیشنهادی هم قبولش دارد', () async {
    final (store, importer) = await _setup();
    final inbox = [_sms(_mellatSender, _mellatBody, 0)];
    await importer.importAll(inbox);

    final d = (await _diagnose(store, inbox)).items.single;
    expect(d.verdict, SmsVerdict.counted);
    expect(d.stored, isNotNull);
    expect(d.parsed.bankId, 'mellat');
    expect(d.parsed.accountRef, '1000000009');
    expect(d.strict.accepts, isTrue);
    expect(d.droppedByStrict, isFalse);
  });

  test('شارژ اعتبار دیجی‌پی: با قانون ثبت نمی‌شود («شماره حساب/کارت ندارد»)', () async {
    final (store, importer) = await _setup();
    final inbox = [_sms(_digipaySender, _digipayBody, 0)];
    await importer.importAll(inbox);

    final report = await _diagnose(store, inbox);
    final d = report.items.single;
    expect(d.verdict, SmsVerdict.noId);
    expect(d.stored, isNull);
    expect(d.strict.missing, [StrictCheck.noId]);
    expect(d.droppedByStrict, isFalse);
    expect(report.droppedByStrictCount, 0);
  });

  test('تراکنشِ بی‌شماره‌ای که پیش از قانون ثبت شده «خلافِ قانون» است', () async {
    final (store, _) = await _setup();
    final sms = _sms(_digipaySender, _digipayBody, 0);
    // ثبتِ قدیمی (پیش از قانون): «پرداخت» → هزینه‌ی ۵ میلیون تومانی
    await store.saveParsed(const SmsParser().parse(sender: sms.sender, body: sms.body),
        sender: sms.sender, receivedAt: sms.receivedAt);

    final report = await _diagnose(store, [sms]);
    final d = report.items.single;
    expect(d.verdict, SmsVerdict.counted);
    expect(d.stored!.amountRial, 50000000);
    expect(d.droppedByStrict, isTrue);
    expect(report.droppedByStrictCount, 1);
  });

  test('نسخه‌ی سرورِ همین پیامک (بی‌متن) «ثبت نشده» حساب نمی‌شود', () async {
    final (store, _) = await _setup();
    final sms = _sms(_mellatSender, _mellatBody, 0);
    store.addRecord(TransactionRecord(
      id: 'remote-1',
      kind: 'expense',
      amountRial: 1250000,
      origin: 'remote',
      sourceMessageHash: smsFingerprint(
          sender: sms.sender, body: sms.body, receivedAt: sms.receivedAt),
      createdAt: _t0,
      updatedAt: _t0,
    ));
    final d = (await _diagnose(store, [sms])).items.single;
    expect(d.verdict, SmsVerdict.counted);
    expect(d.stored!.id, 'remote-1');
  });

  test('رمز پویا رد می‌شود و دلیلش گفته می‌شود', () async {
    final (store, importer) = await _setup();
    final inbox = [_sms(_mellatSender, _otpBody, 0)];
    await importer.importAll(inbox);

    final d = (await _diagnose(store, inbox)).items.single;
    expect(d.verdict, SmsVerdict.otp);
    expect(d.stored, isNull);
    expect(d.strict.missing, contains(StrictCheck.notTx));
  });

  test('پیامکِ تکراری (همان متن، چند دقیقه بعد) «تکراری» نشان داده می‌شود', () async {
    final (store, importer) = await _setup();
    final inbox = [
      _sms(_mellatSender, _mellatBody, 0),
      _sms(_mellatSender, _mellatBody, 3),
    ];
    await importer.importAll(inbox);

    final report = await _diagnose(store, inbox);
    expect(report.count(SmsVerdict.counted), 1);
    expect(report.count(SmsVerdict.duplicate), 1);
  });

  test('پیامکی که کاربر حذف کرده «حذف شده» است، نه «ثبت نشده»', () async {
    final (store, importer) = await _setup();
    final inbox = [_sms(_mellatSender, _mellatBody, 0)];
    await importer.importAll(inbox);
    await store.deleteTransaction((await store.getAll()).single.id);

    final d = (await _diagnose(store, inbox)).items.single;
    expect(d.verdict, SmsVerdict.deleted);
    expect(d.droppedByStrict, isFalse); // از قبل در جمع نیست
    expect(d.strict.accepts, isTrue); // یعنی به‌اشتباه حذف شده؛ «برگرداندن» دارد
  });

  test('پیامکِ تراکنشی که هنوز وارد نشده «ثبت نشده» است', () async {
    final (store, _) = await _setup();
    final d = (await _diagnose(store, [_sms(_mellatSender, _mellatBody, 0)])).items.single;
    expect(d.verdict, SmsVerdict.notImported);
  });

  test('تراکنشی که پیامکش دیگر در صندوق نیست هم بررسی می‌شود', () async {
    final (store, importer) = await _setup();
    await importer.importAll([_sms(_mellatSender, _mellatBody, 0)]);

    final d = (await _diagnose(store, const [])).items.single;
    expect(d.inInbox, isFalse);
    expect(d.verdict, SmsVerdict.counted);
    expect(d.strict.accepts, isTrue);
  });

  test('پیامکِ مبلغ‌دار از فرستنده‌ی غیرمجاز فقط شمرده می‌شود', () async {
    final (store, _) = await _setup();
    final report = await _diagnose(store, [
      _sms('Shop', 'خرید شما به مبلغ 200,000 ریال ثبت شد', 0),
      _sms('Shop', 'تخفیف 50,000 ریال', 1),
      _sms('+989120000000', 'سلام', 2),
    ]);
    expect(report.items, isEmpty);
    expect(report.notAllowedWithAmount, {'Shop': 2});
  });

  test('جدیدترین اول', () async {
    final (store, importer) = await _setup();
    final inbox = [
      _sms(_digipaySender, _digipayBody, 0),
      _sms(_mellatSender, _mellatBody, 10),
    ];
    await importer.importAll(inbox);
    final report = await _diagnose(store, inbox);
    expect(report.items.map((d) => d.sender), [_mellatSender, _digipaySender]);
  });
}
