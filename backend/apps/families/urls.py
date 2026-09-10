from django.urls import path

from .views import (
    FamilyInviteView,
    FamilyListCreateView,
    FamilyMembershipDetailView,
    FamilyMembersView,
)

urlpatterns = [
    path("", FamilyListCreateView.as_view(), name="family-list-create"),
    path("<uuid:family_id>/members/", FamilyMembersView.as_view(), name="family-members"),
    path(
        "<uuid:family_id>/members/invite/",
        FamilyInviteView.as_view(),
        name="family-invite",
    ),
    path(
        "<uuid:family_id>/members/<uuid:membership_id>/",
        FamilyMembershipDetailView.as_view(),
        name="family-membership-detail",
    ),
]
