from django.contrib import admin

from .models import DeviceHealth, FamilyGroup, FamilyMembership


class MemberInline(admin.TabularInline):
    model = FamilyMembership
    fk_name = "family"
    extra = 1
    fields = ("user", "role", "joined_at")
    readonly_fields = ("joined_at",)
    autocomplete_fields = ("user",)
    verbose_name = "عضو"
    verbose_name_plural = "اعضا"


@admin.register(FamilyGroup)
class FamilyGroupAdmin(admin.ModelAdmin):
    list_display = ("name", "member_names", "created_at")
    search_fields = ("name",)
    inlines = [MemberInline]

    def get_queryset(self, request):
        return super().get_queryset(request).prefetch_related("memberships__user")

    @admin.display(description="اعضا")
    def member_names(self, obj):
        return "، ".join(str(m.user) for m in obj.memberships.all()) or "—"


@admin.register(DeviceHealth)
class DeviceHealthAdmin(admin.ModelAdmin):
    list_display = ("user", "device_id", "app_version", "level", "reported_at", "updated_at")
    list_filter = ("level",)
    readonly_fields = ("user", "device_id", "app_version", "level", "summary", "reported_at", "updated_at")
