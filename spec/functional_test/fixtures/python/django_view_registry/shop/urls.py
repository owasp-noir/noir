from django.urls import include, path

from core.urls import get_model_urls

from . import views  # noqa F401

urlpatterns = [
    path("items/", include(get_model_urls("shop", "item", detail=False))),
    path("items/<int:pk>/", include(get_model_urls("shop", "item"))),
]
