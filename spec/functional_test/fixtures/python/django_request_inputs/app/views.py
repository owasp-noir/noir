from django.conf import settings
from rest_framework import generics, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .serializers import ConfigSerializer
from .utils import flag_from, load_class


def login_view(request):
    form_class = load_class(settings.LOGIN_FORM)
    if request.method == "POST":
        form = form_class(request.POST)
        if form.is_valid():
            user = form.cleaned_data["user"]
    return Response({})


class ValidateAPI(generics.CreateAPIView):
    serializer_class = ConfigSerializer

    def post(self, request, *args, **kwargs):
        return super().post(request, *args, **kwargs)

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(status=204)


class VersionsAPI(generics.RetrieveAPIView):
    def get(self, request, pk):
        verbose = flag_from(request.GET, "verbose", False)
        return Response({})

    def delete(self, request, pk):
        version = request.data.get("version")
        return Response({})


class ItemViewSet(viewsets.GenericViewSet):
    def destroy(self, request, pk=None):
        reason = request.data.get("reason")
        return Response(status=204)

    @action(detail=True, methods=["post", "delete"])
    def notes(self, request, pk=None):
        if request.method == "POST":
            note = request.data["note"]
        elif request.method == "DELETE":
            note_id = request.GET.get("id")
        return Response({})
