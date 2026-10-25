from rest_framework import viewsets

from .serializers import NoteSerializer


class BulkDestroyMixin:
    def bulk_destroy(self, request, *args, **kwargs):
        serializer = NoteSerializer(data=request.data, many=True)
        return serializer


class BaseViewSet(BulkDestroyMixin, viewsets.ModelViewSet):
    def _if_match(self, request):
        return request.META.get("HTTP_IF_MATCH")

    def update(self, request, *args, **kwargs):
        self._if_match(request)
        serializer = self.get_serializer(data=request.data)
        return serializer

    def destroy(self, request, *args, **kwargs):
        serializer = NoteSerializer(data=request.data)
        return serializer
