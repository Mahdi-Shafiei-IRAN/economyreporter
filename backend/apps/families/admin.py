from django.conf import settings
from django.contrib import admin

from .models import FamilyGroup, FamilyMembership


class MemberInline(admin.TabularInline):
    model = FamilyMembership
    fk_name = "family"
    extra = 1
    max_num = settings.FAMILY_MAX_MEMBERS
    fields = ("user", "role", "joined_at")
    readonly_fields = ("joined_at",)
    autocomplete_fields = ("user",)
    verbose_name = "عضو"
    verbose_name_plural = f"اعضا (حداکثر {settings.FAMILY_MAX_MEMBERS} نفر)"


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
