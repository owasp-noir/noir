from rest_framework import viewsets
from rest_framework.response import Response


class SnippetViewSet(viewsets.ViewSet):
    def list(self, request):
        return Response([])

    def create(self, request):
        title = request.data.get("title")
        return Response({}, status=201)

    def retrieve(self, request, pk=None):
        return Response({})

    def update(self, request, pk=None):
        return Response({})

    def partial_update(self, request, pk=None):
        return Response({})

    def destroy(self, request, pk=None):
        return Response(status=204)


# Bound in the views module and mounted from the urlconf by name.
snippet_highlight = SnippetViewSet.as_view({"post": "partial_update"})
