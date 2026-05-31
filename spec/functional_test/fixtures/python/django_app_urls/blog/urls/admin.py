from django.urls import path

from blog import views

urlpatterns = [
    path("dashboard/", views.dashboard),
]
