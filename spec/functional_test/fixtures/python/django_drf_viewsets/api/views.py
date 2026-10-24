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
