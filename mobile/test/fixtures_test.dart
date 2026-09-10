import 'dart:convert';
import 'dart:io';

import 'package:economy/core/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// تست رگرسیون پارسر روی پوشه‌ی نمونه‌های پیامک.
/// هر فایل json در test/fixtures/sms/ یک نمونه است (مصنوعی یا واقعی).
void main() {
  const parser = SmsParser();
  final dir = Directory('test/fixtures/sms');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('پوشه‌ی fixture خالی نیست', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('fixture: $name', () {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final r = parser.parse(
        sender: data['sender'] as String,
        body: data['body'] as String,
      );
      final e = Map<String, dynamic>.from(data['expect'] as Map);

      void check(String key, Object? actual) {
        if (e.containsKey(key)) expect(actual, e[key], reason: '$name → $key');
      }

      check('bankId', r.bankId);
      check('kind', r.kind.name);
      check('amountRial', r.amountRial);
      check('cardLast4', r.cardLast4);
      check('accountRef', r.accountRef);
      check('balanceAfterRial', r.balanceAfterRial);
      check('counterparty', r.counterparty);
      check('needsReview', r.needsReview);
      if (e.containsKey('hasDate')) {
        expect(r.occurredAt != null, e['hasDate'], reason: '$name → hasDate');
      }
    });
  }
}
