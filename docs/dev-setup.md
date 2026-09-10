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

## ۵) مهاجرت به VPS

وقتی سرور خریدی (پیشنهاد: ابر ایرانی مثل آروان/لیارا/پارس‌پک، چون AWS/GCP از ایران بلاک‌اند):

1. `config/settings/production.py`: `DEBUG=False`، `ALLOWED_HOSTS=["yourdomain.ir"]`، اطلاعات DB واقعی، `SECRET_KEY` از env.
2. Postgres روی سرور، مهاجرت داده در صورت نیاز.
3. **HTTPS** با Nginx یا Caddy + دامنه‌ی `.ir` (Caddy گواهی را خودکار می‌گیرد).
4. فایل `network_security_config` توسعه را از اپ بردار؛ آدرس پایه‌ی اپ می‌شود `https://yourdomain.ir/api/v1/`.
5. `USE_TZ = True` و ذخیره‌ی همه‌چیز به UTC از همان ابتدا رعایت شده باشد.

> چون همه‌چیز از روز اول Offline-First است، تغییر آدرس سرور فقط یک تنظیم در اپ است؛ داده‌ی روی گوشی‌ها دست‌نخورده می‌ماند و در اولین Sync به سرور جدید می‌رود.
