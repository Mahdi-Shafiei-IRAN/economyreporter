"""آپلودِ دسته‌ایِ همگام‌سازی: هر آیتم جدا پردازش می‌شود.

قبلاً یک آیتمِ خراب (نامعتبر، مالِ خانواده‌ی دیگر، یا خطای پیش‌بینی‌نشده) کلِ
درخواست را با ۴۰۰/۴۰۴/۵۰۰ رد می‌کرد؛ گوشی هم همان آیتم را هر بار دوباره می‌فرستاد و
همگام‌سازی برای همیشه گیر می‌کرد. حالا نتیجه‌ی هر آیتم جداست و بقیه انجام می‌شوند.
"""
import logging

from django.db import transaction as db_transaction
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError

logger = logging.getLogger(__name__)


def upsert_each(items, upsert):
    """[upsert](item) → (data, created). خروجی: یک dict به‌ازای هر آیتم با `status`:
    created/updated (یا `status`ی که خودِ data دارد، مثلاً `stale`)، `conflict` (شناسه مالِ
    خانواده‌ی دیگر است)، `forbidden` (ردیفِ کاربرِ دیگر)، یا `error` (+detail)."""
    results = []
    for item in items:
        item_id = item.get("id") if isinstance(item, dict) else None
        try:
            with db_transaction.atomic():
                data, created = upsert(item)
            results.append({"status": "created" if created else "updated", **data})
        except NotFound:
            results.append(
                {"id": item_id, "status": "conflict", "detail": "این شناسه مالِ خانواده‌ی دیگری است"}
            )
        except PermissionDenied:
            results.append(
                {"id": item_id, "status": "forbidden", "detail": "این ردیف را کاربرِ دیگری ساخته"}
            )
        except ValidationError as e:
            results.append({"id": item_id, "status": "error", "detail": e.detail})
        except Exception:  # یک آیتمِ خراب نباید کلِ دسته را با ۵۰۰ رد کند
            logger.exception("sync item failed: %s", item_id)
            results.append({"id": item_id, "status": "error", "detail": "خطای سرور در این آیتم"})
    return results
