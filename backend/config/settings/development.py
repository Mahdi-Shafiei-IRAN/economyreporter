"""تنظیمات توسعه — روی کامپیوتر خودت. جزئیات اجرا: docs/dev-setup.md"""

from .base import *  # noqa: F401,F403

DEBUG = True

# در توسعه‌ی محلی، اتصال گوشی از طریق LAN مجاز است.
ALLOWED_HOSTS = ["*"]
