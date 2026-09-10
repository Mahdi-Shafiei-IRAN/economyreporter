from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/auth/", include("apps.users.urls")),
    path("api/v1/family/", include("apps.families.urls")),
    path("api/v1/", include("apps.accounts.urls")),
    path("api/v1/", include("apps.categories.urls")),
    path("api/v1/", include("apps.budgets.urls")),
    path("api/v1/", include("apps.transactions.urls")),
]
