from django.urls import path, include
from rest_framework.routers import DefaultRouter
from shop.api.views import ItemViewSet, ProfileView

router = DefaultRouter()
router.register("items", ItemViewSet)

urlpatterns = [
    path("api/", include(router.urls)),
    path("profile/", ProfileView.as_view()),
    path("orders/", include("shop.orders.urls")),
]
