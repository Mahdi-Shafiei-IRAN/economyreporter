/// رجیستری بانک‌ها و تشخیص بانک از روی فرستنده (قدم اولِ پارس).
///
/// نکته: `senderCodes` (سرشماره‌های عددی سامانه‌ی هر بانک) باید با
/// **نمونه‌ی پیامک واقعی** پر شوند؛ فعلاً بیشتر تشخیص بر پایه‌ی نام فرستنده است.
library;

import 'digit_utils.dart';

/// پروفایل یک بانک برای تشخیص و پارس.
class BankProfile {
  final String id;
  final String name;

  /// زیررشته‌هایی که اگر در فرستنده باشند، این بانک است.
  /// شامل معادل لاتین (کوچک) و فارسی.
  final List<String> senderAliases;

  /// سرشماره‌های عددی دقیق سامانه‌ی بانک. با نمونه‌ی واقعی پر می‌شوند.
  final List<String> senderCodes;

  const BankProfile({
    required this.id,
    required this.name,
    this.senderAliases = const [],
    this.senderCodes = const [],
  });
}

/// فهرست بانک‌های ایران. با نمونه‌ی واقعی گسترش/اصلاح می‌شود.
const List<BankProfile> kBankRegistry = [
  BankProfile(id: 'mellat', name: 'بانک ملت', senderAliases: ['mellat', 'ملت']),
  BankProfile(id: 'melli', name: 'بانک ملی ایران', senderAliases: ['bmi', 'melli', 'ملی']),
  BankProfile(id: 'saderat', name: 'بانک صادرات', senderAliases: ['saderat', 'bsi', 'صادرات']),
  BankProfile(id: 'tejarat', name: 'بانک تجارت', senderAliases: ['tejarat', 'تجارت']),
  BankProfile(id: 'saman', name: 'بانک سامان', senderAliases: ['saman', 'sb24', 'سامان']),
  BankProfile(id: 'pasargad', name: 'بانک پاسارگاد', senderAliases: ['pasargad', 'bpi', 'پاسارگاد']),
  BankProfile(id: 'parsian', name: 'بانک پارسیان', senderAliases: ['parsian', 'پارسیان']),
  BankProfile(id: 'sepah', name: 'بانک سپه', senderAliases: ['sepah', 'سپه']),
  BankProfile(id: 'keshavarzi', name: 'بانک کشاورزی', senderAliases: ['keshavarzi', 'bki', 'کشاورزی']),
  BankProfile(id: 'refah', name: 'بانک رفاه کارگران', senderAliases: ['refah', 'رفاه']),
  BankProfile(id: 'ayandeh', name: 'بانک آینده', senderAliases: ['ayandeh', 'آینده']),
  BankProfile(id: 'eghtesadnovin', name: 'بانک اقتصاد نوین', senderAliases: ['eghtesadnovin', 'enbank', 'اقتصاد نوین', 'اقتصادنوین']),
  BankProfile(id: 'shahr', name: 'بانک شهر', senderAliases: ['shahr', 'بانک شهر']),
  BankProfile(id: 'blu', name: 'بلوبانک', senderAliases: ['blu', 'blubank', 'بلو']),
];

/// پروفایل بانک از روی شناسه (یا null).
BankProfile? bankById(String bankId) {
  for (final bank in kBankRegistry) {
    if (bank.id == bankId) return bank;
  }
  return null;
}

/// نام نمایشی بانک از روی شناسه (برای UI). اگر نبود، خود شناسه.
String bankNameById(String bankId) => bankById(bankId)?.name ?? bankId;

/// قدم اولِ پارس: تشخیص بانک از روی فرستنده. اگر شناخته نشود null برمی‌گرداند.
BankProfile? detectBank(String sender) {
  final s = normalizeForParsing(sender).trim();
  final lower = s.toLowerCase();
  for (final bank in kBankRegistry) {
    if (bank.senderCodes.contains(s)) return bank;
    for (final alias in bank.senderAliases) {
      if (lower.contains(alias)) return bank;
    }
  }
  return null;
}
