from rest_framework.routers import DefaultRouter
from rest_framework_extensions.routers import NestedRouterMixin

from docs import views


class NestingRouter(NestedRouterMixin, DefaultRouter):
    pass


router = NestingRouter()

projects = router.register(r"projects", views.ProjectViewSet, basename="projects")
versions = projects.register(
    r"versions",
    views.VersionViewSet,
    basename="projects-versions",
    parents_query_lookups=["project__slug"],
)
versions.register(
    r"builds",
    views.BuildViewSet,
    basename="projects-versions-builds",
    parents_query_lookups=["project__slug", "version__slug"],
)
# projects.register(r"commented", views.BuildViewSet, parents_query_lookups=["x"])
router.register(r"remote", views.BuildViewSet, basename="remote")

urlpatterns = router.urls
