from djangoblog.api_routers import BulkRouter

from . import views

app_name = 'core-api'

router = BulkRouter()
router.register('nodes', views.NodeViewSet)

urlpatterns = router.urls
