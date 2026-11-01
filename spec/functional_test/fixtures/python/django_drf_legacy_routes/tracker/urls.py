from rest_framework import routers

from . import views

router = routers.DefaultRouter(trailing_slash=False)
router.register(r"issues", views.IssueViewSet, basename="issues")

urlpatterns = router.urls
