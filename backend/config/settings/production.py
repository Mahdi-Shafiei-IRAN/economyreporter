"""تنظیمات تولید — VPS. مقادیر حساس از متغیرهای محیطی/‏.env خوانده می‌شوند."""

from .base import *  # noqa: F401,F403
from .base import env

DEBUG = False

# در تولید حتماً باید تنظیم شوند.
SECRET_KEY = env("SECRET_KEY")
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")

# امنیت HTTPS (پشت nginx/caddy)
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
