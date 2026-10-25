from django.urls import include, path

from views import LoginView, MediaView

urlpatterns = [
    path("login/", LoginView.as_view()),
    path("media/<path:path>", MediaView.as_view()),
    path("shop/", include("shop.urls")),
]
