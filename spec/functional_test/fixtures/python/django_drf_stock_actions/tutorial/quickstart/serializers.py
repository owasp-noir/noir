from django.contrib.auth.models import User
from rest_framework import serializers

from .models import Group


# DRF quickstart: ModelSerializer with a literal Meta.fields list.
class UserSerializer(serializers.HyperlinkedModelSerializer):
    class Meta:
        model = User
        fields = ["url", "username", "email", "groups"]


# DRF tutorial part 1: declared fields.
class SnippetSerializer(serializers.Serializer):
    id = serializers.IntegerField(read_only=True)
    title = serializers.CharField(required=False, allow_blank=True, max_length=100)
    code = serializers.CharField(style={"base_template": "textarea.html"})
    linenos = serializers.BooleanField(required=False)


# `read_only_fields` and the pk are not input.
class GroupSerializer(serializers.ModelSerializer):
    class Meta:
        model = Group
        fields = ("id", "name", "note", "display_name")
        read_only_fields = ("note",)


class LabelSerializer(serializers.Serializer):
    value = serializers.CharField()
    preview = serializers.CharField(read_only=True)
    revision = serializers.IntegerField()

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["revision"].read_only = True


class ExtendedGroupSerializer(GroupSerializer):
    labels = LabelSerializer(many=True)
    computed = LabelSerializer(read_only=True)

    class Meta(GroupSerializer.Meta):
        fields = (*GroupSerializer.Meta.fields, "labels") + ("computed",)


class FullGroupSerializer(serializers.ModelSerializer):
    class Meta:
        model = Group
        fields = "__all__"
        read_only_fields = ("note",)
        extra_kwargs = {"color": {"read_only": True}}
