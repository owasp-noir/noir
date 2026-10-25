from rest_framework import viewsets

from . import serializers
from .base import BaseViewSet


class TagViewSet(BaseViewSet):
    serializer_class = serializers.TagSerializer


class ConfigViewSet(viewsets.ViewSet):
    def list(self, request):
        return None

    def patch(self, request):
        return request.data.get("theme")
