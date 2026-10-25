from . import views
from .routers import BulkRouter

router = BulkRouter()
router.register("tags", views.TagViewSet)
router.register("notes", views.NoteViewSet)
router.register("config", views.ConfigViewSet, basename="config")
urlpatterns = router.urls
