from django.urls import include, path

from views import FormOverride, LoginView, MediaView, PingView

urlpatterns = [
    path("login/", LoginView.as_view()),
    path("media/<path:path>", MediaView.as_view()),
    path("shop/", include("shop.urls")),
    path("override/", FormOverride.as_view()),
    path("ping/", PingView.as_view()),
]
