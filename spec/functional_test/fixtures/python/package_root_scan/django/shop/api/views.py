from rest_framework import viewsets
from rest_framework.views import APIView
from rest_framework.permissions import IsAdminUser
from rest_framework.response import Response


class ItemViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAdminUser]

    def list(self, request):
        q = request.query_params.get("q")
        return Response([])


class ProfileView(APIView):
    def get(self, request):
        return Response({})

    def post(self, request):
        name = request.data.get("name")
        return Response({})
