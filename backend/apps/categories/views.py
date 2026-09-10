from rest_framework import viewsets

from apps.common.family import resolve_family, user_family_ids

from .models import Category
from .serializers import CategorySerializer


class CategoryViewSet(viewsets.ModelViewSet):
    serializer_class = CategorySerializer

    def get_queryset(self):
        return Category.objects.filter(
            family_id__in=user_family_ids(self.request.user)
        ).order_by("name")

    def perform_create(self, serializer):
        family = resolve_family(self.request.user, self.request.data.get("family"))
        serializer.save(family=family)
