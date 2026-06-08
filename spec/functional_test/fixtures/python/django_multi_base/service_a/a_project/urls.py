from django.urls import path
from . import views

urlpatterns = [
    path("a-only/", views.a_view),
]
