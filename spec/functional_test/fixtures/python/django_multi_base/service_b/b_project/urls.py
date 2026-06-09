from django.urls import path
from . import views

urlpatterns = [
    path("b-only/", views.b_view),
]
