import 'package:economy/core/sms/raw_sms.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/senders/data/sender_candidates.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('تطبیق فرستنده', () {
    test('شماره با +98، 0098، صفر اول و ارقام فارسی یکی است', () {
      for (final v in [
        '+989121234567',
        '00989121234567',
        '09121234567',
        '۰۹۱۲۱۲۳۴۵۶۷',
        '+98 912 123 4567',
      ]) {
        expect(sameSender('09121234567', v), isTrue, reason: v);
      }
      expect(sameSender('+98300012345', '0300012345'), isTrue);
      expect(sameSender('300012345', '98300012345'), isTrue);
    });

    test('شماره‌های متفاوت یا پیشوندی یکی نیستند', () {
      expect(sameSender('09121234567', '09121234568'), isFalse);
      expect(sameSender('3000', '300012345'), isFalse);
      expect(sameSender('', ''), isFalse);
    });

    test('نام فرستنده بدون توجه به فاصله و حروف بزرگ/کوچک', () {
      expect(sameSender('Bank Mellat', 'BANKMELLAT'), isTrue);
      expect(sameSender('BankMellat', 'Mellat'), isFalse);
    });

    test('یافتن فرستنده‌ی مجاز', () {
      const list = [
        AllowedSender(id: '1', address: 'BankMellat', bankId: 'mellat'),
        AllowedSender(id: '2', address: '+98200012345'),
      ];
      expect(findAllowedSender(list, 'bankmellat')?.id, '1');
      expect(findAllowedSender(list, '0200012345')?.id, '2');
      expect(findAllowedSender(list, 'Digikala'), isNull);
    });
  });

  group('پیشنهاد فرستنده‌ها', () {
    final at = DateTime.utc(2026, 9, 10);
    TransactionRecord stored(String id, String sender, String body) => TransactionRecord(
          id: id,
          kind: 'expense',
          amountRial: 1000,
          smsSender: sender,
          smsBody: body,
          smsReceivedAt: at,
          createdAt: at,
          updatedAt: at,
        );

    test('فقط فرستنده‌های مبلغ‌دارِ غیرمجاز، گروه‌شده و به‌ترتیب تعداد', () {
      final inbox = [
        RawSms(sender: 'BankMellat', body: 'خرید مبلغ 50,000 ریال از کارت 1234', receivedAt: at),
        RawSms(sender: 'Digikala', body: 'خرید مبلغ 990,000 ریال با کد تخفیف', receivedAt: at),
        RawSms(
          sender: 'Digikala',
          body: 'پرداخت مبلغ 120,000 ریال سفارش شما',
          receivedAt: at.add(const Duration(hours: 1)),
        ),
        const RawSms(sender: 'Operator', body: 'بسته‌ی اینترنت شما فعال شد'),
        RawSms(sender: '+98200012345', body: 'واریز مبلغ 1,000,000 ریال', receivedAt: at),
      ];
      final result = findSenderCandidates(
        inbox: inbox,
        stored: [
          stored('t1', 'Digikala', 'خرید مبلغ 990,000 ریال با کد تخفیف'),
          stored('t2', '0200012345', 'واریز مبلغ 1,000,000 ریال'),
        ],
        allowed: const [AllowedSender(id: 's', address: 'BankMellat')],
      );

      expect(result.map((c) => c.address), ['Digikala', '+98200012345']);
      expect(result.first.inboxCount, 2);
      expect(result.first.stored.map((t) => t.id), ['t1']);
      expect(result.first.sample, contains('120,000')); // جدیدترین متن
      expect(result.last.stored.single.id, 't2'); // «+98…» و «0…» یک فرستنده‌اند
    });

    test('بانکِ حدسی از نام فرستنده', () {
      final result = findSenderCandidates(
        inbox: [RawSms(sender: 'Saman', body: 'برداشت مبلغ 20,000 ریال', receivedAt: at)],
        stored: const [],
        allowed: const [],
      );
      expect(result.single.bankId, 'saman');
    });

    test('تراکنش‌های عضو دیگر (از سرور) و حذف‌شده‌ها پیشنهاد نمی‌شوند', () {
      final remote = TransactionRecord(
        id: 'r',
        kind: 'expense',
        amountRial: 1000,
        smsSender: 'X',
        smsBody: 'خرید مبلغ 1,000 ریال',
        origin: 'remote',
        createdAt: at,
        updatedAt: at,
      );
      final deleted = stored('d', 'Y', 'خرید مبلغ 1,000 ریال').copyWith(deletedAt: at);
      expect(
        findSenderCandidates(inbox: const [], stored: [remote, deleted], allowed: const []),
        isEmpty,
      );
    });
  });
}
