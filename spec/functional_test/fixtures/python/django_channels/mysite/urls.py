from django.urls import path

from chat import views

urlpatterns = [
    path("index/", views.index),
]
