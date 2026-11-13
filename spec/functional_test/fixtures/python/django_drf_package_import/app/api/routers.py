from rest_framework.routers import DefaultRouter

from app.api.views import WidgetViewSet

API_VERSION = "1"

router = DefaultRouter()
router.register("widgets", WidgetViewSet, basename="shared-widgets")
