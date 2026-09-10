from rest_framework import viewsets
from rest_framework.exceptions import NotFound

from apps.common.family import resolve_family, user_family_ids

from .models import BankAccount, Card
from .serializers import BankAccountSerializer, CardSerializer


class BankAccountViewSet(viewsets.ModelViewSet):
    serializer_class = BankAccountSerializer

    def get_queryset(self):
        return BankAccount.objects.filter(
            family_id__in=user_family_ids(self.request.user)
        ).order_by("created_at")

    def perform_create(self, serializer):
        family_id = self.request.data.get("family")
        family = resolve_family(self.request.user, family_id)
        serializer.save(family=family, owner=self.request.user)


class CardViewSet(viewsets.ModelViewSet):
    serializer_class = CardSerializer

    def get_queryset(self):
        return Card.objects.filter(
            account__family_id__in=user_family_ids(self.request.user)
        ).order_by("created_at")

    def perform_create(self, serializer):
        account = serializer.validated_data["account"]
        if account.family_id not in user_family_ids(self.request.user):
            raise NotFound()  # نمی‌توان به حسابی که نمی‌بینی کارت وصل کرد
        serializer.save()
