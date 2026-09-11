# راه‌اندازی محیط توسعه — سرور روی کامپیوتر خودت

> فعلاً سرور = کامپیوتر خودت (ویندوز). گوشی از طریق **همان Wi-Fi** به آن وصل می‌شود. بعداً که VPS خریدی، همین کد با تغییر تنظیمات منتقل می‌شود ([بخش مهاجرت](#۵-مهاجرت-به-vps)).

## ۱) پیش‌نیازها روی ویندوز

- **Python 3.12+**
- **PostgreSQL** — دو گزینه:
  - نصب مستقیم PostgreSQL روی ویندوز، یا
  - **Docker Desktop** و اجرای فقط Postgres در کانتینر (ساده‌تر برای پاک‌سازی). برای MVP همین کافی است و نیازی به Docker برای خود Django نیست.
- **Flutter SDK** + Android Studio (برای بیلد اپ و اجرای روی گوشی واقعی).
- گوشی و کامپیوتر روی **یک شبکه‌ی Wi-Fi**.

## ۲) اجرای بک‌اند به‌صورت قابل‌دسترس در شبکه‌ی محلی

Django به‌صورت پیش‌فرض فقط روی `127.0.0.1` گوش می‌دهد و از گوشی دیده نمی‌شود. باید روی همه‌ی اینترفیس‌ها گوش بدهد:

```bash
python manage.py runserver 0.0.0.0:8000
```

آدرس IP کامپیوترت را در شبکه‌ی محلی پیدا کن:

```bash
ipconfig
```

دنبال `IPv4 Address` کارت Wi-Fi بگرد (چیزی مثل `192.168.1.23`). آدرس پایه‌ی API برای اپ می‌شود:

```text
http://192.168.1.23:8000/api/v1/
```

در `config/settings/development.py`:

```python
ALLOWED_HOSTS = ["*"]        # فقط در توسعه‌ی محلی
DEBUG = True
```

## ۳) اجازه‌ی عبور از فایروال ویندوز

ویندوز به‌صورت پیش‌فرض اتصال ورودی به پورت ۸۰۰۰ را می‌بندد. یک قانون ورودی اضافه کن (PowerShell با دسترسی Administrator):

```powershell
New-NetFirewallRule -DisplayName "Django Dev 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

بعد از اتمام توسعه می‌توانی این قانون را حذف کنی:

```powershell
Remove-NetFirewallRule -DisplayName "Django Dev 8000"
```

## ۴) اجازه‌ی ترافیک HTTP (بدون TLS) در اپ اندروید — فقط توسعه

روی شبکه‌ی محلی HTTPS نداری، پس اپ باید موقتاً HTTP ساده را بپذیرد. در `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<network-security-config>
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="true">192.168.1.23</domain>
  </domain-config>
</network-security-config>
```

و در `AndroidManifest.xml` این فایل را به `<application android:networkSecurityConfig="@xml/network_security_config">` وصل کن. **این فقط برای توسعه است**؛ در تولید حذف و به HTTPS سوییچ می‌شود.

## ۵) اجرای بک‌اند Django (فاز ۲)

پیش‌فرض دیتابیس در توسعه **SQLite** است (بدون نیاز به نصب Postgres). محیط مجازی و پکیج‌ها یک‌بار:

```bash
cd backend
python -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements/development.txt
```

سپس مایگریشن، ساخت کاربر مدیر، و اجرا:

```bash
.venv\Scripts\python.exe manage.py migrate
```

```bash
.venv\Scripts\python.exe manage.py createsuperuser
```

(شماره موبایل و رمز مدیر را می‌پرسد.) **پنل مدیریت** فارسی: `http://127.0.0.1:8000/admin/` —
ساخت خانواده و کاربرها (شماره موبایل + نام + رمز + خانواده)، تغییر رمز، غیرفعال/حذف
کاربر، دیدن تراکنش‌ها و عمل «نامعتبر کن». ثبت‌نام عمومی در API وجود ندارد. راهنمای
قدم‌به‌قدم: `docs/run-on-phone.md` بخش ۳.

برای اینکه گوشی روی شبکه‌ی محلی به بک‌اند وصل شود، روی همه‌ی اینترفیس‌ها گوش بده (بخش‌های ۲ و ۳ بالا برای IP و فایروال):

```bash
.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8000
```

آدرس پایه‌ی API: `http://<IP کامپیوتر>:8000/api/v1/`

endpointهای آماده:

```text
POST /api/v1/auth/login/        ورود (phone, password) → access + refresh (JWT)
POST /api/v1/auth/refresh/      تازه‌سازی access
GET  /api/v1/auth/me/           کاربر جاری (نیازمند توکن)
GET/POST /api/v1/family/        لیست/ساخت خانواده
GET  /api/v1/family/{id}/members/
POST /api/v1/family/{id}/members/invite/     (فقط مالک)
DELETE /api/v1/family/{id}/members/{mid}/     (فقط مالک)

# فاز ۴: CRUD + Sync + داشبورد (همه محدود به خانواده‌ی کاربر)
GET/POST/PATCH/DELETE /api/v1/accounts/    و  /api/v1/cards/
GET/POST/PATCH/DELETE /api/v1/categories/  و  /api/v1/budgets/
GET/POST/PATCH/DELETE /api/v1/transactions/    (فیلتر: kind, category, account, card, member, needs_review)
POST /api/v1/sync/transactions/     آپلود دسته‌ای idempotent (بدنه: device_id, transactions[])
GET  /api/v1/dashboard/summary/     جمع درآمد/هزینه/مانده + تفکیک عضو/دسته/کارت (?from=&to=)
```

### سوییچ به PostgreSQL (اختیاری، مثلاً با Docker)

اگر خواستی همین حالا با Postgres کار کنی (به‌جای SQLite):

```bash
docker run --name economy-pg -e POSTGRES_DB=economy -e POSTGRES_USER=economy -e POSTGRES_PASSWORD=economy -p 5432:5432 -d postgres
```

بعد در `backend/.env` بگذار:

```env
DB_ENGINE=postgres
DB_NAME=economy
DB_USER=economy
DB_PASSWORD=economy
DB_HOST=127.0.0.1
DB_PORT=5432
```

و دوباره `migrate` بزن. (روی سرور واقعی هم همین متغیرها استفاده می‌شوند.)

## ۶) مهاجرت به VPS

وقتی سرور خریدی (پیشنهاد: ابر ایرانی مثل آروان/لیارا/پارس‌پک، چون AWS/GCP از ایران بلاک‌اند):

1. `config/settings/production.py`: `DEBUG=False`، `ALLOWED_HOSTS=["yourdomain.ir"]`، اطلاعات DB واقعی، `SECRET_KEY` از env.
2. Postgres روی سرور، مهاجرت داده در صورت نیاز؛ بعد `migrate` و `createsuperuser` (حساب مدیر پنل، با شماره موبایل).
3. `python manage.py collectstatic` و سرو کردن `/static/` با Nginx/Caddy — با `DEBUG=False` خود جنگو فایل‌های ظاهر پنل ادمین را سرو نمی‌کند.
4. **HTTPS** با Nginx یا Caddy + دامنه‌ی `.ir` (Caddy گواهی را خودکار می‌گیرد).
5. فایل `network_security_config` توسعه را از اپ بردار؛ آدرس پایه‌ی اپ می‌شود `https://yourdomain.ir/api/v1/`.
6. `USE_TZ = True` و ذخیره‌ی همه‌چیز به UTC از همان ابتدا رعایت شده باشد.

> چون همه‌چیز از روز اول Offline-First است، تغییر آدرس سرور فقط یک تنظیم در اپ است؛ داده‌ی روی گوشی‌ها دست‌نخورده می‌ماند و در اولین Sync به سرور جدید می‌رود.
