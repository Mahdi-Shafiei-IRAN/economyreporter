# TODO — وضعیت پیشرفت پروژه‌ی economy

> این فایل هر سری به‌روزرسانی می‌شود. ✅ = انجام و تست‌شده، 🔄 = در حال انجام، ⬜ = مانده.
> آخرین به‌روزرسانی: ۱۴۰۵/۰۶/۱۹ (2026-09-10)

## راه‌اندازی اولیه
- ✅ ساختار مستندات `docs/` (معماری، پارسر، نقشه‌ی راه، dev-setup)
- ✅ `CLAUDE.md` (قوانین دائمی پروژه)
- ✅ `.gitignore` (Django + Flutter)
- ✅ اسکلت پروژه‌ی Flutter در `mobile/`

## فاز ۱ — برش عمودی نازک (تک‌گوشی، آفلاین)
هدف: پیامک → تشخیص بانک از سرشماره → استخراج مبلغ → ذخیره در SQLite → لیست.

- ✅ **هسته‌ی پارسر (Dart خالص، تست‌شده — ۱۶ تست پاس، analyze تمیز)**
  - ✅ نرمال‌سازی ارقام فارسی/عربی → لاتین + حذف جداکننده‌ها (`digit_utils.dart`)
  - ✅ رجیستری بانک‌ها (`bank_registry.dart`) — بر پایه‌ی نام فرستنده. ⚠️ سرشماره‌های عددی (`senderCodes`) با نمونه‌ی واقعی پر شوند.
  - ✅ تشخیص بانک از روی فرستنده (قدم اول پارس)
  - ✅ استخراج مبلغ (ریال، با تبدیل تومان) + نوع تراکنش (income/expense/transfer)
  - ✅ استخراج مانده و ۴ رقم کارت (شامل کارت ماسک‌شده)
  - ⬜ استخراج پذیرنده/counterparty (فیلد آماده است؛ منطق استخراج با نمونه‌ی واقعی)
  - ⬜ استخراج تاریخ (نیازمند تبدیل تقویم شمسی — بعداً)
  - ✅ مدل `ParsedTransaction` (`models.dart`)
  - ✅ **تست واحد و اجرای واقعی (`flutter test`) — پاس شد**
- ✅ **لایه‌ی SQLite (تست‌شده — روی ویندوز با sqflite_common_ffi)**
  - ✅ اسکیما و باز کردن دیتابیس (`core/database/app_database.dart`) — جدول‌های transactions و outbox + ایندکس‌ها + ایندکس یکتای جزئی ضدتکرار
  - ✅ مدل ردیف `TransactionRecord` + نگاشت از/به Map و از `ParsedTransaction`
  - ✅ اثرانگشت پیامک `smsFingerprint` (`core/sms/sms_fingerprint.dart`)
  - ✅ مخزن `TransactionRepository`: درج، ضدتکرار، لیست، `summary` (درآمد/هزینه/مانده با حذف transfer)
  - ✅ کمک‌تابع تست FFI با fallback به winsqlite3 (`test/helpers/db_test_helper.dart`)
  - ✅ **۶ تست دیتابیس — همه پاس**
- ✅ **UI داشبورد (تست‌شده با widget test — headless، بدون گوشی)**
  - ✅ قالب‌بندی پول (نمایش به تومان) `core/format/money_format.dart`
  - ✅ `DashboardController` (بارگذاری جمع/لیست + افزودن از پیامک)
  - ✅ اینترفیس `TransactionStore` (تزریق‌پذیر: SQLite در اپ، fake در تست)
  - ✅ صفحه‌ی داشبورد: کارت جمع (درآمد/هزینه/مانده) + لیست + شیت «افزودن پیامک»
  - ✅ چیدمان راست‌به‌چپ + بازنویسی `main.dart`
  - ✅ **۱۰ تست UI/format (مجموع کل: ۳۱ تست، همه پاس)**
- ⬜ SMS Receiver اندروید (دریافت پیامک واقعی) — نیازمند گوشی/امولاتور + Android SDK
- ⬜ **اجرای بصری اپ روی گوشی/امولاتور** (تا این نباشد، دریافت واقعی پیامک تست نمی‌شود)

> وضعیت فاز ۱: هسته‌ی منطقی (پارسر + دیتابیس + UI) کامل و تست‌شده. تنها بخش وابسته به سخت‌افزار (دریافت پیامک و اجرای بصری) مانده که به Android SDK + گوشی/امولاتور نیاز دارد.

## فاز ۲ — پایه‌ی بک‌اند Django (روی کامپیوتر کاربر)
- ✅ **پروژه‌ی Django + DRF + JWT (تست‌شده — ۱۴ تست + smoke واقعی روی سرور)**
  - ✅ ساختار `backend/` با settings چندمحیطی (base/development/production)
  - ✅ دیتابیس تزریق‌پذیر: SQLite پیش‌فرض dev، Postgres با متغیر محیطی
  - ✅ کاربر سفارشی با UUID و ورود با ایمیل (`apps/users`)
  - ✅ endpointهای auth: register / login (JWT) / refresh / me
  - ✅ خانواده و عضویت (`apps/families`) + سقف ۳ نفر (server-side)
  - ✅ endpointهای family: ساخت/لیست، اعضا، دعوت (فقط مالک)، حذف عضو
  - ✅ Authorization سطح‌شیء (غیرعضو=۴۰۴ تا وجود خانواده لو نرود، عضو غیرمالک=۴۰۳)
  - ✅ requirements/{base,development,production}.txt + `.env.example`
  - ✅ **۱۴ تست (`manage.py test`) همه پاس + تست عملی روی سرور زنده (register/login/me/family)**
- ⬜ اجرای روی Postgres واقعی (وقتی سرور خریده شد یا Docker بالا آمد)

## فاز ۳ — مدل داده‌ی اصلی بک‌اند
- ✅ **مدل‌ها + مایگریشن + تست (۱۴ تست مدل، مجموع بک‌اند: ۲۸ پاس)**
  - ✅ `apps/accounts`: `BankAccount` (+ bank_id هم‌راستا با پارسر) و `Card` (unique در هر حساب)
  - ✅ `apps/categories`: `Category` (unique نام در هر خانواده)
  - ✅ `apps/transactions`: `Transaction` — نوع income/expense/**transfer**، `amount_rial`، `balance_after_rial`، `counterparty`، `transfer_group`، سه زمان (transaction_date/client_created_at/server_received_at)، ایندکس‌ها، و **ایندکس یکتای جزئی ضدتکرار** (family+source_message_hash)
  - ✅ `apps/budgets`: `Budget` (unique در category+period)
  - ✅ رفتار SET_NULL هنگام حذف دسته/حساب/کارت (تراکنش حفظ می‌شود)

## فاز ۴ — CRUD API + Sync + داشبورد
- ✅ **API کامل + تست (۱۶ تست API، مجموع بک‌اند: ۴۴ پاس)**
  - ✅ `apps/common`: تشخیص خانواده‌ی کاربر (`resolve_family`) + ابزار تست
  - ✅ ViewSet برای accounts/cards/categories/budgets/transactions با **ایزوله‌سازی خانواده** (queryset محدود + غیرعضو ۴۰۴)
  - ✅ فیلترهای تراکنش: kind/category/account/card/member/needs_review
  - ✅ **`POST /api/v1/sync/transactions/`** — آپلود دسته‌ای idempotent با پاسخ per-item (created/already_exists/error)؛ dedup دولایه (id + اثرانگشت)
  - ✅ **`GET /api/v1/dashboard/summary/`** — جمع درآمد/هزینه/مانده + تفکیک عضو/دسته/کارت (transfer حذف می‌شود)
  - ✅ تراکنش id از دستگاه می‌گیرد (idempotency)؛ ولیدیشن ارجاع‌ها (حساب/کارت/دسته هم‌خانواده)

## فازهای بعدی (خلاصه — جزئیات در docs/roadmap.md)
- ⬜ فاز −۱: جمع‌آوری ۵۰–۱۰۰ پیامک واقعی (نمونه‌ها را کاربر بعداً می‌فرستد)
- ⬜ فاز ۵: پایه‌ی Flutter (auth، repository، api client)
- ⬜ فاز ۶: موتور تراکنش محلی + صف بازبینی
- ⬜ فاز ۷: پارسر کامل همه‌ی بانک‌ها + تست رگرسیون
- ⬜ فاز ۸: Background Sync (outbox، batch، retry)
- ⬜ فاز ۹: داشبورد خانواده + تطبیق مانده
- ⬜ فاز ۱۰: Conflict & Recovery
- ⬜ فاز ۱۱: سخت‌سازی امنیت
- ⬜ فاز ۱۲: تولید (VPS، HTTPS، بکاپ)

## یادداشت‌ها
- نمونه‌ی پیامک واقعی هنوز نرسیده؛ رجیستری سرشماره و Regexها با نمونه‌های واقعی کامل/اصلاح می‌شوند.
- adb/Android SDK روی PATH نیست؛ برای تست روی گوشی باید تنظیم شود (فاز SMS Receiver).
