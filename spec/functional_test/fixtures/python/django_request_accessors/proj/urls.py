from django.urls import path
from app import views

urlpatterns = [
    path("headers/", views.headers),
    path("upload/", views.upload),
]
