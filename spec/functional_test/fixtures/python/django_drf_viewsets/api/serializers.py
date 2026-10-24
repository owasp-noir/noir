from rest_framework import serializers


class IdsSerializer(serializers.Serializer):
    ids = serializers.ListField(child=serializers.IntegerField())


class BulkSerializer(IdsSerializer):
    reason = serializers.CharField(required=False)
    summary = serializers.CharField(
        read_only=True,
    )
    kind = serializers.SerializerMethodField()

    def get_kind(self, obj):
        return "bulk"
