from rest_framework import serializers

from apps.users.serializers import UserSerializer

from .models import FamilyGroup, FamilyMembership


class FamilyMembershipSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)

    class Meta:
        model = FamilyMembership
        fields = ["id", "user", "role", "joined_at"]
        read_only_fields = fields


class FamilyGroupSerializer(serializers.ModelSerializer):
    my_role = serializers.SerializerMethodField()
    member_count = serializers.SerializerMethodField()

    class Meta:
        model = FamilyGroup
        fields = ["id", "name", "created_at", "my_role", "member_count"]
        read_only_fields = ["id", "created_at", "my_role", "member_count"]

    def get_my_role(self, obj):
        user = self.context["request"].user
        membership = obj.memberships.filter(user=user).first()
        return membership.role if membership else None

    def get_member_count(self, obj):
        return obj.memberships.count()


class InviteSerializer(serializers.Serializer):
    phone = serializers.CharField(max_length=20)
