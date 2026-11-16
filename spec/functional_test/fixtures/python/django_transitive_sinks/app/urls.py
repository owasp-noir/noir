from django.urls import path
from . import views

urlpatterns = [
    path("export/", views.export),
    path("report/", views.report),
    path("ambiguous/", views.ambiguous),
    path("cycle/", views.cycle),
    path("ping/", views.ping),
]
