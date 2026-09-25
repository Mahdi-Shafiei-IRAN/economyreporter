# معماری سیستم

> این سند مرجع اصلی طراحی است. تصمیم‌های قطعی: بک‌اند **Django REST + PostgreSQL**، موبایل **Flutter + SQLite**، معماری **Offline-First**، سرور فعلی **کامپیوتر خود کاربر** (بعداً VPS ایرانی).

## فهرست
1. [اصل حاکم بر داده](#۱-اصل-حاکم-بر-داده)
2. [نمای کلی](#۲-نمای-کلی)
3. [واقعیت چنددستگاهی](#۳-واقعیت-چنددستگاهی)
4. [مدل داده‌ی سرور](#۴-مدل-دادهی-سرور)
5. [مدل داده‌ی محلی موبایل](#۵-مدل-دادهی-محلی-موبایل)
6. [موتور Sync](#۶-موتور-sync)
7. [جلوگیری از تراکنش تکراری](#۷-جلوگیری-از-تراکنش-تکراری)
8. [API](#۸-api)
9. [داشبورد و گزارش](#۹-داشبورد-و-گزارش)
10. [دسته‌بندی](#۱۰-دستهبندی)
11. [امنیت](#۱۱-امنیت)
12. [پول: ریال و تومان](#۱۲-پول-ریال-و-تومان)

---

## ۱) اصل حاکم بر داده

داده‌ی اصلی همیشه از دستگاه به سرور جریان دارد، نه برعکس:

```text
SMS → Parse → Local SQLite → pending → Batch Sync → Server → PostgreSQL
```

اگر اینترنت قطع باشد، اپ باید کامل کار کند (ثبت، ویرایش، نمایش، جمع‌بندی). سرور فقط برای **ترکیب داده‌ی ۳ گوشی** و پشتیبان‌گیری است، نه برای کارکرد روزمره.

هر تراکنش از لحظه‌ی ساخت روی گوشی یک **UUID** می‌گیرد که در کل چرخه‌ی `Local → Sync → Retry → Server` ثابت می‌ماند. این UUID پایه‌ی idempotency است.

---

## ۲) نمای کلی

```text
                    ┌──────────────────────┐
                    │   Android (×۳ گوشی)  │
                    │                      │
                    │ Flutter UI           │
                    │        │             │
                    │ Repository           │
                    │        │             │
                    │ Local SQLite         │
                    │        │             │
                    │ Outbox / Sync Queue  │
                    │        │             │
                    │ SMS Receiver         │
                    │        │             │
                    │ SMS Parser (per-bank)│
                    └────────┼─────────────┘
                             │  HTTPS/JWT (در توسعه: HTTP روی LAN)
                             ▼
                 ┌────────────────────────┐
                 │       Django DRF       │
                 │ Auth · Family · Accounts│
                 │ Transactions · Sync    │
                 │ Categories · Dashboard │
                 │ Budgets · Reconcile    │
                 └───────────┬────────────┘
                             ▼
                     ┌───────────────┐
                     │  PostgreSQL   │
                     └───────────────┘
```

برای MVP **بدون Redis/Celery/worker جدا**. یک Django + Postgres کافی است. Celery فقط وقتی گزارش سنگین یا زمان‌بندی‌شده لازم شد اضافه می‌شود.

ساختار بک‌اند:

```text
backend/
├── config/
│   ├── settings/{base,development,production}.py
│   ├── urls.py · asgi.py · wsgi.py
├── apps/
│   ├── users/        # کاربر سفارشی
│   ├── families/     # خانواده و عضویت
│   ├── accounts/     # حساب و کارت
│   ├── categories/   # دسته‌ها
│   ├── transactions/ # تراکنش (قلب سیستم)
│   ├── sync/         # endpoint دسته‌ای idempotent
│   ├── budgets/      # بودجه‌ی هر دسته
│   └── reports/      # داشبورد و تطبیق مانده
├── common/           # مدل پایه، permissionها، utils
├── requirements/
└── manage.py
```

---

## ۳) واقعیت چنددستگاهی

این یک سیستم **۳ دستگاه → ۱ اکانت خانواده‌ی مشترک** است. نکات کلیدی:

- هر گوشی فقط پیامک کارت‌های **خودش** را می‌گیرد. پس هر عضو، تراکنش‌های خودش را محلی پارس و sync می‌کند.
- هر دستگاه `device_id` یکتا دارد که در payload هر Sync می‌آید.
- **خطر ثبت دوبل بین دستگاه‌ها:** وقتی علی به سارا کارت‌به‌کارت می‌زند، هر دو گوشی پیامک می‌گیرند. این «یک جابه‌جایی» است، نه دو تراکنش. سرور باید این را تشخیص دهد (بخش [۷](#۷-جلوگیری-از-تراکنش-تکراری)).

---

## ۴) مدل داده‌ی سرور

قراردادهای مشترک همه‌ی مدل‌ها: کلید اصلی `UUIDField`، فیلدهای `created_at`/`updated_at`، و ایزوله‌سازی بر اساس `family`.

### User (سفارشی)
```python
class User(AbstractUser):
    username = None
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=11, unique=True)  # 09xxxxxxxxx — شناسه‌ی ورود
    full_name = models.CharField(max_length=150, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    USERNAME_FIELD = "phone"
```
ورود با **شماره موبایل + رمز**؛ هر شکلِ شماره (`+98…`، ارقام فارسی، بدون صفر) به `09…`
استاندارد می‌شود. کاربر را فقط مدیر در **پنل ادمین** (`/admin/`، فارسی) می‌سازد و به
خانواده وصل می‌کند؛ ثبت‌نام عمومی نداریم.

### FamilyGroup و FamilyMembership
```python
class FamilyGroup(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=150)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class FamilyMembership(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(FamilyGroup, on_delete=models.CASCADE, related_name="memberships")
    user   = models.ForeignKey(User, on_delete=models.CASCADE, related_name="family_memberships")
    role   = models.CharField(max_length=20, choices=[("owner","Owner"),("member","Member")])
    joined_at = models.DateTimeField(auto_now_add=True)
    class Meta:
        constraints = [models.UniqueConstraint(fields=["family","user"], name="unique_family_member")]
```
سقف اعضا (۳ نفر) سمت سرور enforce می‌شود.

### BankAccount و Card
حساب و کارت را یکی نگیر؛ یک حساب می‌تواند چند کارت داشته باشد.
```python
class BankAccount(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(FamilyGroup, on_delete=models.CASCADE, related_name="accounts")
    owner  = models.ForeignKey(User, on_delete=models.CASCADE, related_name="accounts")
    bank_name = models.CharField(max_length=100)
    account_number_masked = models.CharField(max_length=32, blank=True)
    account_type = models.CharField(max_length=30, default="checking")
    currency = models.CharField(max_length=3, default="IRR")
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

class Card(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    account   = models.ForeignKey(BankAccount, on_delete=models.CASCADE, related_name="cards")
    card_last4 = models.CharField(max_length=4)   # فقط ۴ رقم آخر — هرگز PAN کامل
    card_label = models.CharField(max_length=100, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
```

### Category
```python
class Category(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family = models.ForeignKey(FamilyGroup, on_delete=models.CASCADE, related_name="categories")
    name  = models.CharField(max_length=100)
    icon  = models.CharField(max_length=100, blank=True)
    color = models.CharField(max_length=20, blank=True)
    is_system = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
```
دسته‌های پیش‌فرض: خوراک، حمل‌ونقل، خرید، قبوض، سلامت، آموزش، سرگرمی، حقوق/درآمد، کارمزد، سایر.

### Transaction (قلب سیستم)
نسبت به طرح اولیه، **چهار افزوده‌ی حیاتی**: نوع `transfer`، مبلغ کانونی به ریال + مقدار خام، `balance_after` (مانده)، و `counterparty` (طرف حساب/پذیرنده).

```python
class Transaction(models.Model):
    class Kind(models.TextChoices):
        INCOME   = "income"
        EXPENSE  = "expense"
        TRANSFER = "transfer"   # جابه‌جایی داخلی — در جمع درآمد/هزینه شمرده نمی‌شود

    class Source(models.TextChoices):
        SMS          = "sms"
        MANUAL       = "manual"
        NOTIFICATION = "notification"

    id     = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)  # از دستگاه می‌آید
    family = models.ForeignKey(FamilyGroup, on_delete=models.CASCADE, related_name="transactions")
    owner  = models.ForeignKey(User, on_delete=models.CASCADE, related_name="transactions")

    account  = models.ForeignKey(BankAccount, on_delete=models.SET_NULL, null=True, blank=True)
    card     = models.ForeignKey(Card, on_delete=models.SET_NULL, null=True, blank=True)
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, blank=True)

    kind = models.CharField(max_length=10, choices=Kind.choices)

    # پول: مبلغ کانونی همیشه به ریال (عدد صحیح؛ ریال/تومان جزء اعشاری ندارند)
    amount_rial       = models.BigIntegerField()
    balance_after_rial = models.BigIntegerField(null=True, blank=True)  # «مانده» داخل پیامک
    raw_amount = models.CharField(max_length=32, blank=True)  # آنچه پیامک نوشته بود (audit)
    raw_unit   = models.CharField(max_length=8, default="IRR") # rial | toman

    counterparty = models.CharField(max_length=200, blank=True)  # نام فروشگاه/پایانه/کارت مقصد
    description  = models.TextField(blank=True)

    # برای transfer: دو طرف با یک شناسه به هم وصل می‌شوند
    transfer_group = models.UUIDField(null=True, blank=True, db_index=True)

    # منبع و ضدتکرار
    source = models.CharField(max_length=20, choices=Source.choices, default=Source.SMS)
    source_message_hash = models.CharField(max_length=64, blank=True, db_index=True)
    device_id = models.CharField(max_length=64, blank=True)

    # وضعیت بازبینی
    needs_review = models.BooleanField(default=False)  # اطمینان پارسر پایین یا دسته نامشخص

    # زمان‌ها (همه UTC)
    transaction_date  = models.DateTimeField()             # زمان واقعی رخداد (از پیامک)
    client_created_at = models.DateTimeField(null=True, blank=True)  # زمان ساخت روی دستگاه
    server_received_at = models.DateTimeField(auto_now_add=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["family", "transaction_date"]),
            models.Index(fields=["family", "owner"]),
            models.Index(fields=["family", "category"]),
            models.Index(fields=["family", "card"]),
        ]
```

**چرا سه زمان جدا؟** اگر فقط زمان سرور را داشته باشی، ترتیب واقعی تراکنش‌ها را از دست می‌دهی (پیامک ساعت ۱۴:۰۰ می‌رسد، ساعت ۱۴:۳۰ اینترنت وصل می‌شود). `transaction_date` برای گزارش، `client_created_at` برای ترتیب، `server_received_at` برای audit.

### Budget
```python
class Budget(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    family   = models.ForeignKey(FamilyGroup, on_delete=models.CASCADE, related_name="budgets")
    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="budgets")
    period   = models.CharField(max_length=10, default="monthly")  # monthly | weekly
    limit_rial = models.BigIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)
```

---

## ۵) مدل داده‌ی محلی موبایل

جدول‌های SQLite تقریباً آینه‌ی سرورند، به‌علاوه‌ی مدیریت Sync:

```text
users · families · accounts · cards · categories · budgets
transactions            # با ستون‌های sync_status و ...
outbox                  # صف payloadهای منتظر ارسال
sms_parser_rules        # قواعد پارس، قابل به‌روزرسانی از سرور
```

به‌جای یک flag دوحالته‌ی `is_synced`، از **Outbox Pattern** با وضعیت چندحالته استفاده می‌شود:

```text
sync_status ∈ { pending, syncing, synced, failed }
```

چون در دنیای واقعی: درخواست در حال ارسال است / سرور خطا می‌دهد / شبکه قطع می‌شود / رکورد چندبار retry می‌شود / سرور قبول کرده ولی پاسخ گم شده.

```sql
CREATE TABLE outbox (
    transaction_id TEXT PRIMARY KEY,
    payload        TEXT NOT NULL,     -- JSON تراکنش
    status         TEXT NOT NULL,     -- pending | syncing | synced | failed
    retry_count    INTEGER DEFAULT 0,
    last_attempt_at TEXT,
    next_retry_at   TEXT,
    last_error      TEXT
);
```

معماری لایه‌ای موبایل (UI هرگز مستقیم با SQLite کار نمی‌کند):

```text
Presentation → Application/UseCases → Repository → (Local SQLite + Remote API)
```

```text
lib/
├── core/{database, network, auth, sync}/
├── features/{auth, dashboard, transactions, accounts, categories, family}/
└── main.dart
```

---

## ۶) موتور Sync

**سمت موبایل:**
```text
SMS دریافت → Parse → ساخت UUID → ذخیره در SQLite (needs_review در صورت لزوم)
→ outbox.status = pending → آیا شبکه هست؟ → بله → Background Worker → POST دسته‌ای
```
- به‌صورت **دسته‌ای** (مثلاً تا ۵۰ تراکنش در هر درخواست)، نه یک HTTP request به‌ازای هر تراکنش.
- Retry با exponential backoff: `۳۰ ثانیه → ۲ دقیقه → ۱۰ دقیقه → ۳۰ دقیقه`.

**سمت سرور** (باید atomic و idempotent باشد):
```text
POST /sync → احراز هویت → بررسی مالکیت خانواده → اعتبارسنجی account/card/category
→ تراکنش atomic → bulk upsert → بازگشت وضعیت هر آیتم (created | already_exists)
```

**همگام‌سازی entityهای قابل‌ویرایش** (دسته، توضیح، نام حساب): سیاست ساده‌ی `last-write-wins` بر اساس `updated_at` برای MVP کافی است. خودِ تراکنش‌های SMS تقریباً immutable‌اند، پس conflict کم است.

---

## ۷) جلوگیری از تراکنش تکراری

سه لایه، به ترتیب اولویت:

1. **UUID تراکنش (idempotency اصلی):** `id` روی دستگاه ساخته می‌شود و کلید اصلی Postgres است. اگر همان UUID دوباره POST شود (چون پاسخ قبلی گم شده بود)، سرور به‌جای ساخت رکورد جدید، `already_exists` برمی‌گرداند. endpoint صراحتاً **upsert** رفتار می‌کند.

2. **`source_message_hash`:** برای جلوگیری از دوباره‌پارس‌شدن یک پیامک:
   ```text
   SHA256(sender + normalized_body + received_timestamp_bucket)
   ```
   این را **کلید یکتای مطلق نکن** — دو پیامک واقعی ممکن است متن مشابه داشته باشند؛ فقط سیگنال کمکی است.

3. **ضدتکرار چنددستگاهی (heuristic سمت سرور):** برای کارت‌به‌کارت بین دو عضو خانواده که روی دو گوشی پیامک می‌شود. یک pass تطبیق:
   > اگر دو تراکنش در یک خانواده، `amount_rial` برابر، `transaction_date` در بازه‌ی ±چند دقیقه، یکی خروجی و دیگری ورودی، و روی دو حساب متفاوت باشند → یک **transfer** تلقی و با `transfer_group` مشترک به هم لینک شوند و در جمع درآمد/هزینه فقط یک‌بار (یا خنثی) شمرده شوند.

---

## ۸) API

پایه: `/api/v1/`

```http
# Auth (JWT: access + refresh)
POST /auth/login/  (phone + password)   POST /auth/refresh/   GET /auth/me/
# ثبت‌نام عمومی نیست؛ کاربر و خانواده در پنل ادمین (/admin/) ساخته می‌شوند.

# Family (سقف ۳ عضو، server-side)
GET/POST /family/     GET /family/members/     POST /family/members/invite/     DELETE /family/members/{id}/
# سلامتِ برنامه روی گوشی‌ها: هر گوشی خلاصه‌ی خودش را می‌فرستد (یک ردیف برای کاربر+گوشی)؛
# مدیر گوشیِ همه‌ی اعضا را می‌بیند، عضو فقط خودش را. فقط شمارش/نام بانک/مبلغ/نسخه —
# بدونِ متنِ پیامک، شماره‌ی حساب/کارت و سرشماره.
GET/POST /family/health/

# Accounts & Cards
GET/POST /accounts/   GET/PATCH/DELETE /accounts/{id}/
GET/POST /accounts/{account_id}/cards/   PATCH/DELETE /cards/{id}/

# Categories & Budgets
GET/POST /categories/   PATCH/DELETE /categories/{id}/
GET/POST /budgets/      PATCH/DELETE /budgets/{id}/

# Transactions
GET/POST /transactions/   GET/PATCH/DELETE /transactions/{id}/
# فیلترها:
GET /transactions/?from=..&to=..&member_id=..&category_id=..&account_id=..&card_id=..&kind=expense&needs_review=true

# Sync دسته‌ای (مهم‌ترین endpoint)
POST /sync/transactions/

# Dashboard
GET /dashboard/summary/?from=..&to=..
```

**نمونه‌ی درخواست Sync:**
```json
{
  "device_id": "9e8f...",
  "transactions": [
    { "id": "1f14c...", "account_id": "...", "card_id": "...", "category_id": "...",
      "kind": "expense", "amount_rial": 2500000, "balance_after_rial": 43000000,
      "counterparty": "فروشگاه رفاه", "transaction_date": "2026-09-10T12:20:00Z",
      "source": "sms", "client_created_at": "2026-09-10T12:20:04Z" }
  ]
}
```
**نمونه‌ی پاسخ:**
```json
{ "success": true, "results": [
  { "id": "1f14c...", "status": "created" },
  { "id": "2a83...",  "status": "already_exists" }
]}
```

---

## ۹) داشبورد و گزارش

به‌جای اینکه Flutter همه‌ی تراکنش‌ها را بگیرد و خودش جمع بزند، سرور جمع‌بندی می‌کند:

```http
GET /api/v1/dashboard/summary/?from=2026-09-01&to=2026-09-30
```
```json
{
  "period": { "from": "2026-09-01", "to": "2026-09-30" },
  "family": { "income": 850000000, "expenses": 420000000, "balance": 430000000 },
  "members":    [ { "id": "...", "name": "علی", "expenses": 180000000 } ],
  "categories": [ { "category": "خوراک", "amount": 90000000 } ],
  "cards":      [ { "card_last4": "1234", "amount": 60000000 } ]
}
```
> همه‌ی مبالغ خروجی به **ریال**‌اند؛ تبدیل به تومان سمت نمایش انجام می‌شود.

کوئری‌های اصلی: `SUM(amount_rial) GROUP BY kind / owner / category / card`، با ایندکس روی `(family, transaction_date)` و بقیه‌ی ستون‌های فیلتر. `kind='transfer'` از جمع درآمد/هزینه کنار گذاشته می‌شود.

**تطبیق مانده (Reconciliation):** با `balance_after_rial` می‌توان مانده‌ی جاری هر حساب را بازسازی کرد و فهمید پیامکی جا افتاده (وقتی مانده‌ی دو تراکنش پیاپی با مبلغ بین‌شان جور در نمی‌آید). این اعتماد کاربر را می‌سازد و خطای «پیامک گم‌شده» را می‌گیرد.

---

## ۱۰) دسته‌بندی

سه سطح، ولی برای MVP فقط سطح ۱ و ۲:

- **سطح ۱ — قاعده‌ی ثابت:** بر پایه‌ی نام پذیرنده/کلیدواژه. مثال ایرانی: اسنپ/تپسی → حمل‌ونقل، دیجی‌کالا → خرید، داروخانه → سلامت، قبض/شارژ → قبوض، کارمزد بانکی → کارمزد.
- **سطح ۲ — قاعده‌ی کاربر:** کاربر می‌گوید «هرچه شامل X بود → دسته‌ی Y».
- **سطح ۳ — ML (بعداً):** فعلاً لازم نیست.

قواعد **محلی** اجرا می‌شوند (تا آفلاین هم کار کند) ولی می‌توانند از سرور **به‌روزرسانی** شوند:
```text
Local rules  +  Remote rule synchronization
```
هر تراکنشی که دسته‌اش نامشخص ماند `needs_review=true` می‌شود و در **صف بازبینی** می‌نشیند تا کاربر سریع تأیید/اصلاح کند.

---

## ۱۱) امنیت

داده مالی است؛ امنیت را به فاز آخر موکول نکن.

- **حداقل‌ها:** HTTPS (در تولید)، JWT، هش رمز، اعتبارسنجی ورودی، rate limiting.
- **مهم‌تر از UUID، Authorization سطح‌شیء است.** هر API باید بررسی کند که منبع درخواستی به **خانواده‌ی همان کاربر** تعلق دارد. کاربر خانواده‌ی A نباید با عوض‌کردن UUID، تراکنش خانواده‌ی B را ببیند. UUID امنیت نیست؛ Authorization امنیت است.
- **موبایل:** JWT در Android Keystore (از طریق secure storage) نگه داشته شود، نه SQLite عادی. پایگاه محلی هم بهتر است رمزنگاری‌شده باشد (SQLCipher).
- **پیامک هرگز به سرور نرود:** فقط تراکنش ساختاریافته بالا برود. متن خام SMS نه لاگ شود نه sync.

---

## ۱۲) پول: ریال و تومان

این بخش منشأ رایج‌ترین باگ‌هاست:

- پیامک بانک‌ها تقریباً همیشه به **ریال** است؛ خانواده به **تومان** فکر می‌کند (۱ تومان = ۱۰ ریال).
- **قانون پروژه:** مبلغ کانونی همیشه در `amount_rial` (عدد صحیح، ریال) ذخیره می‌شود. `raw_amount` و `raw_unit` آنچه پیامک گفته بود را برای audit نگه می‌دارند. تبدیل به تومان **فقط در لایه‌ی نمایش** انجام می‌شود.
- ریال و تومان جزء اعشاری ندارند → استفاده از `BigIntegerField`، نه float.
