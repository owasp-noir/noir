from rest_framework import viewsets
from rest_framework.response import Response


class NodeViewSet(viewsets.ReadOnlyModelViewSet):

    def list(self, request):
        region = request.query_params.get('region')
        return Response(region)
