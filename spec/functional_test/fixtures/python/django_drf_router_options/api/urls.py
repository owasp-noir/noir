from django.conf import settings
from rest_framework import routers
from . import views

# trailing_slash=False drops the `/` DRF appends to every route.
router = routers.DefaultRouter(trailing_slash=False)
router.register("tags", views.TagViewSet)
router.register("extra" + settings.ROUTE_SUFFIX, views.TagViewSet)
urlpatterns = router.urls
