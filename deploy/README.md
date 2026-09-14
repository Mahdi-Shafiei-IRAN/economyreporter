# راه‌اندازی روی سرور (اوبونتو ۲۴)

این پوشه یک نصب‌کننده‌ی خودکار دارد که پروژه را روی سرور بالا می‌آورد. همه‌چیز با نامِ
`economy` جدا و مستقل ساخته می‌شود، پس با پروژه‌های دیگرِ همان سرور (مثل knight) قاطی
نمی‌شود.

## این نصب‌کننده چه می‌سازد؟

| بخش | نام | جای آن |
|-----|-----|--------|
| کاربر سیستم | `economy` | فقط همین پروژه با آن اجرا می‌شود |
| پوشه‌ها | `/opt/economy` | کد، venv، `.env`، پشتیبان‌ها |
| دیتابیس | دیتابیس و نقش `economy` در PostgreSQL | جدا از بقیه |
| سرویس | `economy.service` (gunicorn روی سوکت یونیکس) | با systemd |
| وب‌سرور | یک server block در nginx به نام `economy` | بر اساس دامنه |
| ابزار مدیریت | `economyctl` | برای به‌روزرسانی، لاگ، پشتیبان و... |

**اصل جداسازی:** هر پروژه کاربر، پوشه، دیتابیس، سرویس و بلوکِ nginxِ خودش را دارد. تنها
چیزِ مشترکِ اجتناب‌ناپذیر روی هر سرور، **پورت‌های ۸۰/۴۴۳ و خودِ nginx** است؛ راهِ تمیزِ
کنارِ هم گذاشتن چند پروژه این است که به هرکدام یک **زیردامنه** بدهی (مثلاً
`economy.example.ir` و `knight.example.ir`) و همان nginxِ سیستم برای هرکدام یک بلوک جدا
داشته باشد. (اگر knight را با Docker و روی پورت دیگری بالا می‌آوری، تداخلی نیست.)

---

## پیش‌نیاز

- سرور اوبونتو ۲۴.۰۴ با دسترسی `root` یا `sudo` (SSH).
- **یک دامنه یا زیردامنه** که رکورد `A` آن به IP این سرور اشاره کند (برای HTTPS لازم است؛
  پنل ادمین روی HTTP امن نیست چون کوکی‌ها فقط روی HTTPS ذخیره می‌شوند). دامنه‌ی `.ir` هم
  با Let's Encrypt گواهی می‌گیرد.
- اگر هنوز دامنه نداری، می‌شود اول با حالت آزمایشیِ `--no-ssl` روی IP بالا آورد و بعد که
  دامنه گرفتی دوباره با `--domain` اجرا کرد.

---

## مرحله‌به‌مرحله

### ۱) به سرور وصل شو
از روی کامپیوتر خودت:
```bash
ssh root@SERVER_IP
```

### ۲) دامنه را به سرور وصل کن (اگر دامنه داری)
در پنل دامنه‌ات یک رکورد `A` بساز:
```
economy.example.ir   →   SERVER_IP
```
چند دقیقه تا چند ساعت طول می‌کشد تا DNS پخش شود. برای تست:
```bash
dig +short economy.example.ir     # باید IP سرورت را نشان دهد
```

### ۳) نصب‌کننده را بگیر و اجرا کن
فقط کافی است مخزن را clone کنی و اسکریپت را اجرا کنی؛ خود اسکریپت بقیه‌ی کد را در
`/opt/economy` می‌گذارد:
```bash
git clone https://github.com/Mahdi-Shafiei-IRAN/economyreporter.git
cd economyreporter
sudo bash deploy/install.sh --domain economy.example.ir --email you@example.com
```
- `--domain` : دامنه‌ای که در مرحله‌ی ۲ ساختی.
- `--email`  : برای گواهی SSL (اعلان انقضا از Let's Encrypt به این ایمیل می‌رود).

نصب‌کننده خودش این‌ها را انجام می‌دهد: نصب پایتون/PostgreSQL/nginx، ساخت کاربر و دیتابیس،
`venv`، `.env` با `SECRET_KEY` تازه و رمز دیتابیسِ تصادفی، `migrate`، `collectstatic`،
سرویس systemd، بلوک nginx، فایروال، و گرفتنِ گواهی HTTPS.

> **حالت بدون دامنه (فقط تست):**
> ```bash
> sudo bash deploy/install.sh --no-ssl
> ```
> روی `http://SERVER_IP` بالا می‌آید. چون HTTPS نیست، کوکی‌های امن خاموش می‌شوند تا ورود
> به پنل ممکن باشد — این حالت را فقط برای امتحان استفاده کن، نه واقعی.

### ۴) حساب مدیر را بساز
بعد از پایان نصب:
```bash
sudo economyctl superuser
```
شماره موبایل و رمز می‌پرسد. با همین وارد پنل می‌شوی.

### ۵) وارد پنل مدیریت شو
در مرورگر:
```
https://economy.example.ir/admin/
```
اینجا خانواده و کاربرها را می‌سازی (شماره موبایل + نام + رمز + خانواده). راهنمای کاملِ
کار با پنل در `docs/run-on-phone.md` بخش ۳ است.

### ۶) اپ موبایل را به سرور وصل کن
APK را با آدرس سرور دوباره بساز (روی کامپیوتر خودت، نه سرور):
```bash
cd mobile
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://economy.example.ir/api/v1
```
خروجی: `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — این را روی گوشی‌ها
نصب کن. (نسخه‌ی HTTPS دیگر به تنظیمات cleartextِ شبکه‌ی محلی نیازی ندارد.)

---

## سرورهایی که به گیت‌هاب دسترسی ندارند (اینترنت ایران)

اگر سرور نمی‌تواند به github.com وصل شود (خطای timeout روی پورت 443)، نصب‌کننده خودش از
**همان نسخه‌ای که اسکریپت را از داخلش اجرا می‌کنی** کد را کپی می‌کند (نیازی به گیت‌هاب نیست).
اگر pip هم به pypi.org نرسید، یک آینه‌ی ایرانی بده:

```bash
sudo bash deploy/install.sh --domain koalaverifyshop.ir --email you@example.com      --pip-index https://mirror-pypi.runflare.com/simple
```

یا برای تست اول روی IP بدون HTTPS:
```bash
sudo bash deploy/install.sh --no-ssl --pip-index https://mirror-pypi.runflare.com/simple
```

به‌روزرسانی هم از همان پوشه‌ی محلی انجام می‌شود (economyctl update). اگر گواهی Let's Encrypt
هم به‌خاطر فیلترینگ گرفته نشد، از **Cloudflare Origin Certificate** استفاده کن (رایگان، بدون
نیاز به دسترسی سرور به خارج).

## به‌روزرسانی درون‌برنامه (بدون فروشگاه)

اپ خودش `‏<آدرس سرور>/updates/version.json` را چک می‌کند؛ اگر `versionCode` جدیدتر بود، به
کاربر پیشنهاد می‌دهد و APK را از سرور دانلود و نصب می‌کند (نیازمند اجازه‌ی یک‌باره‌ی «نصب
برنامه»). nginx پوشه‌ی `/opt/economy/updates` را روی مسیر `/updates/` سرو می‌کند.

انتشار یک نسخه‌ی جدید:
```bash
# APK را روی سرور بگذار (scp)، بعد:
sudo economyctl publish-apk /root/economy.apk <versionCode> <versionName> "توضیح تغییرات"
# مثال:
sudo economyctl publish-apk /root/economy.apk 3 1.0.2 "رفع اشکال و نقش‌ها"
```
`versionCode` همان عددِ بعد از `+` در `pubspec.yaml` است (`version: 1.0.2+3` → ۳). گوشی‌هایی
که نسخه‌ی نصب‌شده‌شان کوچک‌تر است، دفعه‌ی بعدِ باز کردن اپ پیام به‌روزرسانی می‌گیرند.

> اولین نسخه‌ی دارای این قابلیت باید یک‌بار دستی نصب شود؛ از آن به بعد درون‌برنامه‌ای است.

## مدیریت روزمره (`economyctl`)

```bash
sudo economyctl status        # وضعیت سرویس
sudo economyctl logs          # لاگ زنده (Ctrl+C برای خروج)
sudo economyctl update        # گرفتن آخرین کد از گیت‌هاب + migrate + collectstatic + ری‌استارت
sudo economyctl restart       # ری‌استارت
sudo economyctl superuser     # ساخت مدیر جدید
sudo economyctl passwd 0912…  # تغییر رمز یک کاربر
sudo economyctl backup        # پشتیبان دیتابیس در /opt/economy/backups
sudo economyctl env           # ویرایش .env و ری‌استارت
sudo economyctl renew-cert    # تمدید/گرفتن دوباره‌ی گواهی SSL
sudo economyctl help          # همه‌ی دستورها
```

**به‌روزرسانی بعد از هر تغییرِ کد:** کد را روی گیت‌هاب push کن، بعد روی سرور:
```bash
sudo economyctl update
```

---

## گذاشتن پروژه‌ی دوم روی همان سرور (مثلاً knight)

چون این پروژه کاملاً نام‌دار است، پروژه‌ی دیگر با نصب‌کننده‌ی خودش تداخلی ندارد. فقط این دو
نکته را رعایت کن تا تمیز بماند:

1. **زیردامنه‌ی جدا:** به هر پروژه یک زیردامنه بده (`economy.example.ir`، `knight.example.ir`).
   هر دو رکورد `A` به همین IP.
2. **پورت ۸۰/۴۴۳ مشترک است:** فقط یک nginx می‌تواند این پورت‌ها را بگیرد.
   - اگر پروژه‌ی دوم هم از nginxِ سیستم استفاده می‌کند (مثل همین نصب‌کننده)، هرکدام یک فایل
     جدا در `/etc/nginx/sites-available/` دارند و با `server_name` از هم جدا می‌شوند —
     تداخلی نیست.
   - اگر پروژه‌ی دوم Docker است و nginxِ خودش را دارد، آن را روی یک پورت دیگر (مثلاً ۸۰۸۰)
     ببند و بگذار nginxِ سیستم جلوی آن reverse-proxy باشد؛ یا nginxِ داخل Docker را خاموش
     کن و از همین nginxِ سیستم استفاده کن.

هر پروژه دیتابیس و کاربر سیستم و سرویس systemd جدا دارد؛ حذف یکی به دیگری کاری ندارد.

---

## حذف کامل این پروژه از سرور

```bash
sudo systemctl disable --now economy
sudo rm /etc/systemd/system/economy.service /etc/nginx/sites-enabled/economy \
        /etc/nginx/sites-available/economy /usr/local/bin/economyctl
sudo systemctl daemon-reload && sudo systemctl reload nginx
sudo -u postgres dropdb economy && sudo -u postgres dropuser economy
sudo deluser --remove-home economy
```

---

## عیب‌یابی

- **سرویس بالا نمی‌آید:** `sudo economyctl logs` — معمولاً یا دیتابیس یا `.env`.
- **گواهی SSL گرفته نشد:** DNS دامنه هنوز به IP سرور اشاره نمی‌کند. با `dig +short domain`
  چک کن، بعد `sudo economyctl renew-cert`.
- **پنل ادمین بدون استایل است:** `sudo economyctl static` را بزن (collectstatic).
- **«CSRF verification failed» در پنل:** دامنه باید در `ALLOWED_HOSTS` باشد و از HTTPS باز
  شود؛ `sudo economyctl env` و مقدار `ALLOWED_HOSTS` را چک کن.
- **از گوشی وصل نمی‌شود:** آدرس اپ باید `https://<دامنه>/api/v1` باشد و فایروال وب باز
  (`sudo ufw status`).
