from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response


class WidgetViewSet(viewsets.ModelViewSet):
    lookup_field = 'pk'
    # Without project settings or a backend, these do not enable search.
    search_fields = ['name']

    @action(detail=True, methods=['post'])
    def activate(self, request, pk=None):
        reason = request.data.get('reason')
        return Response(reason)


class GadgetViewSet(viewsets.ReadOnlyModelViewSet):
    lookup_url_kwarg = 'gadget_id'

    def list(self, request):
        kind = request.query_params.get('kind')
        return Response(kind)
