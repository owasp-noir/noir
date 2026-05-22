from rest_framework.routers import DefaultRouter

from . import views


api_router = DefaultRouter()
api_router.register(r'library-media', views.MediaViewSet, basename='library-media')

direct_imported_router = DefaultRouter()
direct_imported_router.register(r'direct-media', views.MediaViewSet, basename='direct-media')
