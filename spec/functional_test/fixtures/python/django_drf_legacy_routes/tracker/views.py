from rest_framework import viewsets
from rest_framework import decorators

from tracker.decorators import list_route
from tracker.mixins import VotedResourceMixin


class IssueViewSet(VotedResourceMixin, viewsets.ModelViewSet):
    @list_route(methods=["get"])
    def filters_data(self, request):
        project = request.QUERY_PARAMS.get("project")
        return project

    @list_route(methods=["POST"], url_path="bulk-create")
    def bulk_create(self, request):
        items = request.DATA.get("bulk_issues")
        return items

    @list_route()
    def by_ref(self, request):
        return None

    @decorators.detail_route(methods=["get", "put"])
    def history(self, request, pk=None):
        return None

    # @list_route(methods=["delete"])
    def list_route_helper(self, request):
        return None
