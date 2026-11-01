from django.urls import path

from proj.views import home

urlpatterns = [
    path("projects/", home),
]
