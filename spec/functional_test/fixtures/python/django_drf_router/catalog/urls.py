# A Django REST Framework app module written the way real ones are: the
# router is a project-wide DefaultRouter subclass imported from a package
# that is not part of this app, and the module publishes `router.urls`
# directly instead of wrapping it in path()/include().
#
# Note what is NOT here: any `django` import. DRF supplies the router, the
# viewsets and the decorators, so a complete, routable Django app can be
# written without naming `django` once.
from myproject.api.routers import BulkRouter

from . import views

app_name = 'catalog-api'

router = BulkRouter()
router.register('widgets', views.WidgetViewSet)
router.register('gadgets', views.GadgetViewSet, basename='gadget')

urlpatterns = router.urls
