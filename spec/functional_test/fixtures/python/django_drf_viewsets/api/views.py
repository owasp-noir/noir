from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.decorators import action
from rest_framework.generics import GenericAPIView
from rest_framework.mixins import RetrieveModelMixin, UpdateModelMixin
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.viewsets import GenericViewSet

from api.serializers import BulkSerializer


class BaseViewSet(
    RetrieveModelMixin,
    UpdateModelMixin,
    GenericViewSet,
):
    permission_classes = (IsAuthenticated,)

    def update(self, request, *args, **kwargs):
        return Response()

    @action(
        methods=["delete"],
        detail=True,
        url_path=r"versions/(?P<version_id>\d+)",
    )
    def delete_version(self, request, pk=None, version_id=None):
        return Response()

    @delete_version.mapping.patch
    def rename_version(self, request, pk=None, version_id=None):
        label = request.data.get("label")
        return Response(label)

    @action(methods=["post"], detail=False)
    def bulk_delete(self, request):
        serializer = BulkSerializer(data=request.data)
        return Response(serializer)


class DocViewSet(BaseViewSet):
    def list(self, request):
        return Response()


class OwnerOnly(BasePermission):
    def has_permission(self, request, view):
        return request.user.is_authenticated


class Anyone(BasePermission):
    def has_permission(self, request, view):
        return True


class OpsMixin(GenericAPIView):
    permission_classes = (OwnerOnly,)

    def post(self, request):
        return Response()


class RunView(OpsMixin):
    serializer_class = None


class OpenView(GenericAPIView):
    permission_classes = [Anyone]

    def get(self, request):
        return Response()


class TokenView(ObtainAuthToken):
    throttle_scope = "login"


def logo(request, filename=None):
    return Response()


import json  # noqa: E402

from rest_framework.pagination import PageNumberPagination  # noqa: E402

from api.serializers import IdsSerializer  # noqa: E402


def paginate(func):
    def inner(self, *args, **kwargs):
        page = self.paginate_queryset(func(self, *args, **kwargs))
        return self.get_paginated_response(page)

    return inner


class FeedPagination(PageNumberPagination):
    page_size_query_param = "size"


class FeedViewSet(GenericViewSet):
    pagination_class = FeedPagination
    serializer_class = IdsSerializer

    def get_queryset(self):
        return self.request.query_params.get("tag")

    @action(methods=["post"], detail=False, serializer_class=BulkSerializer)
    def bulk(self, request):
        serializer = self.serializer_class(data=request.data)
        return Response(serializer)

    @action(methods=["get"], detail=True)
    @paginate
    def related(self, request, pk=None):
        return []

    @action(methods=["get"], detail=False)
    def calendar(self, request):
        return Response(self.get_queryset())

    @action(methods=["get"], detail=False, pagination_class=None)
    @paginate
    def everything(self, request):
        return []


def hook(request, token):
    data = json.loads(request.body.decode())
    return Response(data["message"]["text"])
