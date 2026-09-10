from rest_framework import serializers

from .models import Category


class CategorySerializer(serializers.ModelSerializer):
    family = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Category
        fields = ["id", "family", "name", "icon", "color", "is_system", "created_at"]
        read_only_fields = ["id", "family", "is_system", "created_at"]
