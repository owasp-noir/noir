from django.urls import include, path
from app import views

prefix = ""

pings = [
    path("<int:exitstatus>", views.ping),
]

urlpatterns = [
    path(f"{prefix}login/", views.login),
    path("ping/<uuid:code>/", include(pings)),
    path("slug/<slug:slug>", views.ping_by_slug),
    path("checks/", views.checks),
    path("search/", views.search),
]
