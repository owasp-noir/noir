from django.contrib.auth.models import User
from rest_framework import serializers


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
        fields = ("id", "name", "note")
        read_only_fields = ("note",)
