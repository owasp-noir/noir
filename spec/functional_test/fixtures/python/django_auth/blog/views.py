from django.contrib.auth.decorators import login_required, permission_required
from django.views.generic import DetailView
from django.contrib.auth.mixins import LoginRequiredMixin
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.http import HttpResponse


def public_page(request):
    return HttpResponse("Public content")


@login_required
def post_list(request):
    return HttpResponse("Post list")


@permission_required('blog.add_post')
def post_create(request):
    return HttpResponse("Create post")


class PostDetailView(LoginRequiredMixin, DetailView):
    model = None
    template_name = 'blog/post_detail.html'


class PostAPIView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response({"posts": []})
