"""تنظیمات تولید — VPS. مقادیر حساس از متغیرهای محیطی/‏.env خوانده می‌شوند."""

from .base import *  # noqa: F401,F403
from .base import env

DEBUG = False

# در تولید حتماً باید تنظیم شوند.
SECRET_KEY = env("SECRET_KEY")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")

# دامنه‌هایی که فرم پنل ادمین از آن‌ها POST می‌کند (پشت HTTPS لازم است).
# پیش‌فرض: از روی ALLOWED_HOSTS با https ساخته می‌شود.
CSRF_TRUSTED_ORIGINS = env.list(
    "CSRF_TRUSTED_ORIGINS",
    default=[f"https://{h}" for h in ALLOWED_HOSTS if h not in ("*", "")],
)

# امنیت HTTPS (پشت nginx/caddy). در حالت آزمایشیِ HTTP-only می‌شود این‌ها را در .env
# خاموش کرد تا ورود به پنل ادمین بدون گواهی SSL هم ممکن باشد (فقط برای تست).
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = env.bool("SESSION_COOKIE_SECURE", default=True)
CSRF_COOKIE_SECURE = env.bool("CSRF_COOKIE_SECURE", default=True)
