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

## فاز ۵ — اتصال موبایل به بک‌اند
- ✅ **لایه‌ی شبکه/احراز هویت + تست (۶ تست، مجموع موبایل: ۳۷ پاس)**
  - ✅ `core/config/app_config.dart`: آدرس API (قابل override با --dart-define)
  - ✅ `core/auth/token_store.dart`: ذخیره‌ی امن توکن (اینترفیس + SecureTokenStore با Keystore)
  - ✅ `core/network/api_client.dart`: Dio + interceptor الصاق توکن و **تازه‌سازی خودکار روی 401**
  - ✅ `core/auth/auth_repository.dart`: register/login/me/logout + UserProfile
  - ✅ `features/auth`: `AuthController` + `LoginScreen`
  - ✅ `main.dart`: مسیریابی ورود↔داشبورد + دکمه‌ی خروج
  - ✅ تست: auth_repository (login/me/register/refresh با mock Dio) + widget ورود (موفق/ناموفق)
- ⬜ اتصال بصری واقعی به سرور (نیازمند اجرای اپ روی گوشی/امولاتور + Developer Mode ویندوز برای بیلد پلاگین)

## فاز ۸ — Background Sync (outbox → سرور)
- ✅ **موتور sync + تست (۸ تست، مجموع موبایل: ۴۵ پاس)**
  - ✅ صف‌کردن خودکار تراکنش معتبر در `outbox` هنگام ذخیره (نوع نامشخص صف نمی‌شود)
  - ✅ `core/sync/remote_transaction_api.dart`: کلاینت `POST /sync/transactions/` (اینترفیس + Dio)
  - ✅ `core/sync/sync_service.dart`: خواندن pending، آپلود دسته‌ای (۵۰تایی)، اعمال نتیجه‌ی per-item
  - ✅ idempotency: sync دوباره چیزی نمی‌فرستد؛ created/already_exists → synced
  - ✅ retry با backoff (۳۰ثانیه→۲دق→۱۰دق→۳۰دق)؛ **خطای شبکه آیتم‌ها را گم نمی‌کند**
  - ✅ سیم‌کشی در `main.dart` (sync اولیه) + دکمه‌ی همگام‌سازی در داشبورد
- ⬜ تشخیص خودکار اتصال (connectivity) برای trigger — فعلاً sync اولیه + دکمه‌ی دستی
- ⬜ تست شبکه‌ی واقعی به سرور روی کامپیوتر (نیازمند گوشی/امولاتور)

## فاز ۶ — موتور تراکنش محلی + صف بازبینی
- ✅ **ویرایش/حذف/فیلتر + صف بازبینی + تست (۹ تست، مجموع موبایل: ۵۴ پاس)**
  - ✅ مخزن: `getAll` با فیلتر (kind/needsReview/search)، `needsReviewCount`، `updateTransaction`، `deleteTransaction`
  - ✅ ویرایشِ نوعِ نامشخص به معتبر → خودکار به outbox صف می‌شود؛ حذف، outbox را هم پاک می‌کند
  - ✅ `ReviewScreen`: انتخاب نوع (درآمد/هزینه/انتقال) + تأیید/حذف هر مورد
  - ✅ `EditTransactionSheet`: ویرایش نوع/مبلغ(تومان)/طرف‌حساب/توضیح + حذف (با ضربه روی ردیف)
  - ✅ داشبورد: نشان تعداد بازبینی در نوار بالا + ورود به صف بازبینی
  - ✅ `DashboardController`: needsReviewCount + updateTransaction/deleteTransaction/confirmReview

## فاز ۹ — تطبیق مانده + داشبورد خانواده از سرور
- ✅ **تطبیق مانده + داشبورد سرور + تست (۱۰ تست، مجموع موبایل: ۶۴ پاس)**
  - ✅ `core/reconcile`: `ReconciliationService` — از روی «مانده»ی پیامک، پیامک جاافتاده را کشف می‌کند (به‌تفکیک کارت، جهت برداشت/واریز)
  - ✅ داشبورد: بنر «N مورد احتمال پیامک جاافتاده» + `ReconciliationScreen`
  - ✅ `core/dashboard`: مدل `DashboardSummary` + `RemoteDashboardApi` (اینترفیس + Dio)
  - ✅ `FamilyDashboardScreen`: جمع خانواده از سرور + تفکیک عضو/دسته/کارت (با loading/error)
  - ✅ سیم‌کشی در `main.dart` + دکمه‌ی داشبورد خانواده در نوار بالا

## فاز ۱۱ — سخت‌سازی امنیت
- ✅ **rate limiting + حریم خصوصی + سند (تست: بک‌اند ۴۵، موبایل ۶۵)**
  - ✅ بک‌اند: Rate limiting روی ورود/ثبت‌نام (scope `auth`، ۱۰/دقیقه) ضد brute-force + تست
  - ✅ موبایل: تضمین **عدم ارسال متن خام پیامک** به سرور (تست whitelist کلیدهای payload)
  - ✅ موبایل: توکن در ذخیره‌ی امن پیش‌فرض (Keystore)
  - ✅ `docs/security.md`: جمع‌بندی وضعیت + کارهای مانده (SQLCipher/HTTPS/pinning در فاز تولید)
  - یادآوری: Authorization سطح‌شیء (فاز ۴) و عدم ذخیره‌ی PAN کامل (فاز ۳) از قبل انجام شده‌اند

## فاز ۱۰ — Conflict & Recovery
- ✅ **تست سناریوهای بازیابی (۴ تست، مجموع موبایل: ۶۹ پاس) — همه در اولین اجرا پاس (کد از قبل درست بود)**
  - ✅ پاسخِ گم‌شده / کرش وسط sync → ارسال دوباره تکراری نمی‌سازد (already_exists)
  - ✅ «۱۰ نه ۲۰»: صف‌شدن دوباره پس از کرش، رکورد تکراری روی سرور نمی‌سازد
  - ✅ batch نیمه‌موفق: موفق‌ها synced، خطادار در صف برای retry می‌ماند
  - ✅ قطع شبکه سپس بازگشت: آیتم‌ها گم نمی‌شوند و بعد از برگشت اینترنت (عبور از backoff) sync می‌شوند
  - یادآوری: انقضای JWT با interceptor لایه‌ی شبکه شفاف مدیریت می‌شود (فاز ۵)؛ migration دیتابیس هنگام تغییر schema اضافه می‌شود

## فاز ۷ — پارسر کامل + تست رگرسیون (بخش نرم‌افزاری)
- ✅ **افزودنی‌های پارسر + هارنس رگرسیون (۱۶ تست، مجموع موبایل: ۸۵ پاس)**
  - ✅ استخراج **تاریخ شمسی** و تبدیل به UTC (`core/sms/jalali.dart`) — تاریخ تراکنش پر می‌شود
  - ✅ استخراج **طرف حساب/پذیرنده** («بابت»/«به کارت»/«پذیرنده»)
  - ✅ **هارنس رگرسیون**: `test/fixtures/sms/*.json` + `test/fixtures_test.dart` (۶ نمونه‌ی مصنوعی)
  - ✅ کالیبره با ۲ نمونه‌ی واقعی: مبلغِ چسبیده به فعل بدون واحد، تشخیص بانک از متن، تاریخ دورقمی
  - ✅ **کلید حساب (`account_ref`)** + migration نسخه۲ → **تطبیق مانده برای بانک‌های حساب‌محور** (مثل تجارت) کار می‌کند
  - ⏳ **مانده تا نمونه‌ی بیشتر:** سرشماره‌های عددی بانک‌ها (کاربر بفرستد)، واحدِ پیش‌فرض/تومانیِ «مانده»، دسته‌بندی خودکار
  - 📌 وقتی نمونه رسید: فقط فایل json (با حساب/کارت ماسک‌شده) در پوشه‌ی fixtures اضافه می‌شود

## بیلد و اجرا روی گوشی
- ✅ **لوگو** (کارت بانکی) با flutter_launcher_icons (`assets/icon/`) + نام «مالی خانواده»
- ✅ **APK ساخته شد** — release جدا به‌ازای ABI (arm64 ~۱۶مگ) در `mobile/build/app/outputs/flutter-apk/`
- ✅ ارتقای toolchain اندروید: AGP 8.1 / Gradle 8.4 / Kotlin 1.9 / compileSdk 34 / minSdk 23 / JVM17
- ✅ پروکسی Gradle (`~/.gradle/gradle.properties`) + network security config برای HTTP سرور توسعه
- ✅ `flutter_secure_storage` به ^9.2.2 پین شد (سازگاری با toolchain)
- ✅ کاربر تست ساخته شد: `test@economy.local` / `Test@12345` (+ خانواده)
- ✅ راهنمای کامل: `docs/run-on-phone.md`
- ✅ **SMS Receiver ساخته شد** (نیازمند تست روی گوشی)

## SMS Receiver — خواندن خودکار پیامک
- ✅ **فیلتر رمز پویا (OTP)** — پیامک رمز پویا/یکبارمصرف تراکنش حساب نمی‌شود (تست‌شده)
- ✅ `SmsImporter` (خالص، تست‌شده): فقط تراکنش واقعی وارد می‌شود، تکراری رد می‌شود
- ✅ `SmsInboxService`: مجوز SMS، وارد کردن صندوق هنگام باز شدن اپ، listener زنده (پیش/پس‌زمینه)
- ✅ ذخیره‌ی خودکار + تازه‌سازی داشبورد + **sync خودکار** (داشبورد خانواده هم به‌روز شود)
- ✅ مجوزهای RECEIVE_SMS/READ_SMS + درخواست زمان اجرا
- ⏳ **تست روی گوشی خودت** (APK جدید ساخته شد)

## دسته‌بندی چندتایی + گزارش
- ✅ **مدل دسته‌ها + تخصیص چندتایی با تقسیم مساوی** (schema نسخه۳ + migration + seed ۱۵ دسته)
- ✅ `categorize` (تقسیم مساوی با باقی‌مانده)، `categoryTotals`، `uncategorized` (تست‌شده)
- ✅ صفحه‌ی دسته‌بندی: تیک‌زدن چند دسته + توضیح کوتاه (`CategorizeScreen`)
- ✅ بنر «نیازمند دسته‌بندی» روی داشبورد + فهرست دسته‌بندی‌نشده‌ها
- ✅ **گزارش دسته‌ها** با بازه‌ی امروز/هفته/ماه/کل + نوار نسبت (`CategoryReportScreen`)
- ✅ ۶ تست جدید (مخزن + ویجت)، مجموع موبایل ۱۰۲ تست

## نوتیفیکیشن دسته‌بندی
- ✅ **NotificationService** (flutter_local_notifications): نوتیفیکیشن «تراکنش جدید — دسته‌بندی کن»
- ✅ با لمس نوتیفیکیشن، `CategorizeScreen` همان تراکنش باز می‌شود (navigatorKey + getById)
- ✅ کار در پیش‌زمینه و پس‌زمینه (نوتیفیکیشن از ایزوله‌ی پس‌زمینه)
- ✅ مجوز POST_NOTIFICATIONS + desugaring در build.gradle
- ⏳ تست روی گوشی خودت (APK جدید ساخته شد)

## گزارش نموداری + PDF + دارک‌مود
- ✅ **دارک/لایت/سیستم مود** (`ThemeController` + shared_preferences، دکمه در نوار بالا) — تست‌شده
- ✅ **نمودار دایره‌ای** (fl_chart) در گزارش دسته‌ها + نوار رنگیِ هر دسته
- ✅ **خروجی PDF** گزارش (pdf + printing + فونت فارسی Vazirmatn) با جدول دسته/مبلغ/درصد
- ⏳ تست روی گوشی خودت (APK جدید ساخته شد)

## مدیریت حساب/کارت اعضا (کیف‌ها)
- ✅ **مدل Wallet** + جدول wallets (schema نسخه۴ + migration)
- ✅ مخزن: افزودن/فهرست/حذف کیف + تطبیق با کارت/حساب تراکنش (تست‌شده)
- ✅ `WalletsScreen`: ثبت کارت/حساب با **نام صاحب** + برچسب + بانک + ۴رقم کارت/شماره حساب
- ✅ روی هر تراکنش «صاحب • برچسب» نشان داده می‌شود (کدام شخص و کدام کارت) — تطبیق خودکار
- ✅ دکمه‌ی «حساب‌ها و کارت‌ها» در نوار بالای داشبورد
- ✅ ۵ تست جدید (مخزن + ویجت)، مجموع موبایل ۱۰۹ تست

## خواسته‌های بعدی (اختیاری)
- ⬜ اتصال خودکار کیف به عضو سرور (owner) برای داشبورد خانواده‌ی دقیق‌تر
- ⬜ نمودار میله‌ای روند ماهانه + خروجی PDF کامل‌تر
- 🔒 فاز ۷ (تکمیل): سرشماره‌های عددی بانک‌ها — نیازمند نمونه‌ی بیشتر
- 🔒 فاز ۱۲: تولید (VPS، HTTPS، بکاپ) — نیازمند سرور

## یادداشت‌ها
- IP کامپیوتر سرور: 192.168.1.100 (در app_config.dart). اگر عوض شد، آن‌جا یا با --dart-define بده.
- APK فعلی release امضاشده با کلید debug است (برای تست شخصی). نسخه‌ی فروشگاهی بعداً با کلید release.
