from django.contrib.auth.models import User
from rest_framework import generics, permissions, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.decorators import action
from rest_framework.pagination import CursorPagination, LimitOffsetPagination
from rest_framework.permissions import SAFE_METHODS
from django_filters.rest_framework import DjangoFilterBackend

from tutorial.quickstart.filters import GroupFilter, LabelSearch, Unpaged
from tutorial.quickstart.serializers import (
    ExtendedGroupSerializer, FullGroupSerializer, GroupSerializer, SnippetSerializer, UserSerializer,
)


class UserViewSet(viewsets.ModelViewSet):
    search_fields = ["username"]
    ordering_fields = ["username"]
    filterset_fields = ("is_active",)
    queryset = User.objects.all().order_by("-date_joined")
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]


class SnippetViewSet(viewsets.ModelViewSet):
    serializer_class = SnippetSerializer
    filter_backends = []
    pagination_class = LimitOffsetPagination

    @action(detail=False, pagination_class=CursorPagination, filter_backends=[LabelSearch])
    def feed(self, request):
        return self.paginate_queryset(self.filter_queryset(self.get_queryset()))

    @action(detail=False, pagination_class=Unpaged)
    def summary(self, request):
        items = self.get_queryset()
        return Response(self.paginate_queryset(items) or items)

    @action(detail=False, methods=["post"])
    def import_labels(self, request):
        schema = self.lookup_schema("ExtendedGroupSerializer")
        serializer = schema(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.validated_data)

    def lookup_schema(self, name):
        return self.schemas[self.request.version][name]

    schemas = {"v1": {"ExtendedGroupSerializer": ExtendedGroupSerializer}}


class SnippetCreate(generics.ListCreateAPIView):
    filter_backends = [DjangoFilterBackend]
    filterset_class = GroupFilter
    pagination_class = None
    serializer_class = SnippetSerializer


class GroupDispatch:
    def get_serializer_class(self):
        if hasattr(self, "choose_schema"):
            chosen = self.choose_schema()
        else:
            chosen = self.serializer_class
        return self.version_for(chosen.__name__)

    def version_for(self, name):
        return self.schemas[self.request.version][name]

    schemas = {"v1": {cls.__name__: cls for cls in (ExtendedGroupSerializer, FullGroupSerializer)}}


class GroupUpdate(GroupDispatch, generics.UpdateAPIView):
    filter_backends = []

    def choose_schema(self):
        if self.request.method in SAFE_METHODS:
            return SnippetSerializer
        if self.request.user.is_staff:
            return ExtendedGroupSerializer
        return FullGroupSerializer

    serializer_class = GroupSerializer


# Control: the same serializer handed request.data by hand IS read today.
class SnippetExplicit(APIView):
    def post(self, request, format=None):
        serializer = SnippetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.data)
