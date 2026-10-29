from django.urls import include, path
from rest_framework.routers import DefaultRouter
from proj.views import ArticleViewSet, StatusViewSet, TagViewSet

router = DefaultRouter(trailing_slash=False)
router.register(r'articles', ArticleViewSet)
router.register(r'tags', TagViewSet)
router.register(r'statuses', StatusViewSet)
urlpatterns = [path('api/', include(router.urls))]
