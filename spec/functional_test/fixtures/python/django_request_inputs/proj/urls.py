from django.urls import path
from rest_framework.routers import DefaultRouter

from app import views

router = DefaultRouter()
router.register(r"items", views.ItemViewSet)

urlpatterns = [
    path("login/", views.login_view),
    path("validate/", views.ValidateAPI.as_view()),
    path("versions/<int:pk>/", views.VersionsAPI.as_view()),
    path("article/", views.article),
    path("otp/", views.otp),
    path("legacy/<int:pk>/", views.LegacyAPIView.as_view()),
    *router.urls,
]
