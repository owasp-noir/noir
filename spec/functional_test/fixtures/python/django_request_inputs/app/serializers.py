from rest_framework import serializers


class ConfigSerializer(serializers.Serializer):
    label_config = serializers.CharField()
