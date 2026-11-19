from django.contrib.auth.models import User
from rest_framework import generics, permissions, viewsets
from rest_framework.response import Response
from rest_framework.views import APIView

from tutorial.quickstart.serializers import GroupSerializer, SnippetSerializer, UserSerializer


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("-date_joined")
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]


class SnippetViewSet(viewsets.ModelViewSet):
    serializer_class = SnippetSerializer


class SnippetCreate(generics.ListCreateAPIView):
    serializer_class = SnippetSerializer


class GroupUpdate(generics.UpdateAPIView):
    serializer_class = GroupSerializer


# Control: the same serializer handed request.data by hand IS read today.
class SnippetExplicit(APIView):
    def post(self, request, format=None):
        serializer = SnippetSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(serializer.data)
