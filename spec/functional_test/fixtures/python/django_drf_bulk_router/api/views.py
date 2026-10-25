from rest_framework import viewsets

from . import serializers
from .base import BaseViewSet


class TagViewSet(BaseViewSet):
    serializer_class = serializers.TagSerializer


class NoteViewSet(BaseViewSet):
    serializer_class = serializers.TagSerializer

    def get_serializer_class(self):
        if self.action == "update":
            return serializers.NoteSerializer
        return serializers.TagSerializer


class ConfigViewSet(viewsets.ViewSet):
    def list(self, request):
        return None

    def patch(self, request):
        return request.data.get("theme")

    # Needs a `key` the list route never passes: not routed there.
    def delete(self, request, key):
        return key
