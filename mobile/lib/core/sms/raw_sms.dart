/// یک پیامکِ خام از صندوقِ گوشی (فرستنده + متن + زمانِ رسیدن).
library;

class RawSms {
  final String sender;
  final String body;
  final DateTime? receivedAt;

  const RawSms({required this.sender, required this.body, this.receivedAt});
}
