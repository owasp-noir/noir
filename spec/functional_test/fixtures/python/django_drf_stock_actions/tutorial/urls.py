from django.urls import include, path
from rest_framework import routers

from tutorial.quickstart import views

router = routers.DefaultRouter()
router.register(r"users", views.UserViewSet)
router.register(r"snippets", views.SnippetViewSet, basename="snippet")

urlpatterns = [
    path("", include(router.urls)),
    path("snippet-create/", views.SnippetCreate.as_view()),
    path("group-update/<int:pk>/", views.GroupUpdate.as_view()),
    path("snippet-explicit/", views.SnippetExplicit.as_view()),
]
