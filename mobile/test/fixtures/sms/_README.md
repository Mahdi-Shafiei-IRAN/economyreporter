# نمونه‌های پیامک (fixture) برای تست رگرسیون پارسر

هر فایل `.json` یک نمونه پیامک است با ساختار:

```json
{
  "synthetic": true,
  "sender": "نام/سرشماره فرستنده",
  "body": "متن پیامک",
  "expect": {
    "bankId": "mellat",        // یا null
    "kind": "expense",         // income | expense | transfer | unknown
    "amountRial": 2500000,     // یا null
    "cardLast4": "1234",
    "balanceAfterRial": 43000000,
    "counterparty": "...",
    "hasDate": true,
    "needsReview": false
  }
}
```

- هر کلیدی که در `expect` بیاید، تست بررسی‌اش می‌کند؛ کلیدهای غایب نادیده گرفته می‌شوند.
- فایل‌های فعلی **مصنوعی** (`synthetic: true`) هستند. وقتی نمونه‌ی **واقعی** رسید،
  فقط فایل json جدید (با شماره‌کارت ماسک‌شده) این‌جا اضافه کن؛ تست خودکار پوشش می‌دهد.
- تست: `test/fixtures_test.dart`.
