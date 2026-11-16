from django.urls import re_path
from django.views.static import serve

from . import views

urlpatterns = [
    re_path(r"^media/(?P<path>.*)$", serve, {"document_root": "/srv/media"}),
    re_path(r"^docs/(?P<page>.+)/$", views.docs),
    re_path(r"^users/(?P<username>[\w.@+-]+)/$", views.user),
]
