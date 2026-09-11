"""شماره موبایل = شناسه‌ی ورود.

هر شکلی که تایپ شود (ارقام فارسی، +98، بدون صفر اول، با فاصله) به شکل استاندارد
09xxxxxxxxx تبدیل می‌شود تا ورود، جستجو و یکتایی همیشه یکسان باشد.
"""

import re

from django.core.exceptions import ValidationError

_TO_LATIN = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789")
_SEPARATORS = re.compile(r"[\s\-().]")
MOBILE_RE = re.compile(r"^09\d{9}$")


def normalize_phone(raw):
    """«+98 912 123 4567» / «۰۹۱۲۱۲۳۴۵۶۷» / «9121234567» → «09121234567».

    اگر ورودی شکل موبایل ایران نبود، همان ورودیِ پاک‌شده برمی‌گردد (اعتبارسنجی جداست).
    """
    if raw is None:
        return ""
    s = _SEPARATORS.sub("", str(raw).translate(_TO_LATIN))
    if s.startswith("+"):
        s = s[1:]
    if s.startswith("0098"):
        s = s[4:]
    elif s.startswith("98") and len(s) == 12:
        s = s[2:]
    if len(s) == 10 and s.startswith("9"):
        s = "0" + s
    return s


def validate_mobile(value):
    if not MOBILE_RE.match(value or ""):
        raise ValidationError(
            "شماره موبایل باید ۱۱ رقم باشد و با ۰۹ شروع شود (مثلاً 09121234567).",
            code="invalid_phone",
        )
