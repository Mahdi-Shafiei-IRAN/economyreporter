import uuid

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models

from .phone import normalize_phone, validate_mobile


class UserManager(BaseUserManager):
    """مدیر کاربر با شماره موبایل به‌جای username."""

    use_in_migrations = True

    def _create_user(self, phone, password, **extra_fields):
        phone = normalize_phone(phone)
        if not phone:
            raise ValueError("شماره موبایل الزامی است")
        user = self.model(phone=phone, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, phone, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(phone, password, **extra_fields)

    def create_superuser(self, phone, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("سوپریوزر باید is_staff=True باشد")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("سوپریوزر باید is_superuser=True باشد")
        return self._create_user(phone, password, **extra_fields)

    def get_by_natural_key(self, username):
        # ورود با هر شکلی از شماره (+98، ارقام فارسی، بدون صفر اول).
        return super().get_by_natural_key(normalize_phone(username))


class User(AbstractUser):
    """کاربر با کلید UUID و ورود با شماره موبایل + رمز.

    کاربرها را فقط مدیر در پنل ادمین می‌سازد (ثبت‌نام عمومی نداریم).
    """

    username = None
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    # null فقط برای کاربرهای قدیمیِ ایمیلی که هنوز شماره ندارند (تا مدیر شماره ندهد
    # نمی‌توانند وارد شوند)؛ فرم‌های پنل شماره را اجباری می‌کنند.
    phone = models.CharField(
        "شماره موبایل",
        max_length=11,
        unique=True,
        null=True,
        validators=[validate_mobile],
        help_text="با همین شماره و رمز وارد اپ می‌شود؛ مثلاً 09121234567",
        error_messages={"unique": "کاربری با این شماره موبایل از قبل هست."},
    )
    full_name = models.CharField(
        "نام",
        max_length=150,
        blank=True,
        help_text="همین نام در اپ کنار تراکنش‌ها دیده می‌شود؛ مثلاً «بابا»",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "phone"
    REQUIRED_FIELDS = []

    objects = UserManager()

    class Meta:
        verbose_name = "کاربر"
        verbose_name_plural = "کاربران"

    def __str__(self):
        return " — ".join(p for p in (self.full_name, self.phone) if p) or str(self.id)
