from rest_framework import serializers


class NoteSerializer(serializers.Serializer):
    note = serializers.CharField(write_only=True, required=False)


class TagSerializer(serializers.Serializer):
    name = serializers.CharField()
