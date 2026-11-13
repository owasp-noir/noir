from django.urls import include, path
from rest_framework.routers import DefaultRouter

# A package whose __init__.py re-exports the ViewSet from a submodule.
from app.api.views import WidgetViewSet
# A package whose __init__.py defines the ViewSet itself.
from app.api.legacy import LegacyViewSet
# The second name after a backslash continuation.
from app.api.views.item_viewset import ItemViewSet, \
    GadgetViewSet  # gadgets share the item module
# A router built in another module, bound under an alias after a backslash.
from app.api.routers import API_VERSION, \
    router as shared_router

router = DefaultRouter()
router.register("widgets", WidgetViewSet, basename="widgets")
router.register("legacy", LegacyViewSet)
router.register("items", ItemViewSet, basename="items")
router.register("gadgets", GadgetViewSet, basename="gadgets")

urlpatterns = [
    path("", include(router.urls)),
    path("shared/", include(shared_router.urls)),
]
