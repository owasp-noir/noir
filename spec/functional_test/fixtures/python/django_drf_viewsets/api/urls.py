from django.urls import include, path, re_path
from rest_framework.routers import DefaultRouter

from api.views import DocViewSet, OpenView, RunView, TokenView, logo

router = DefaultRouter()
router.register(r"docs", DocViewSet)

# The router is unpacked into an inline include() whose list wraps over
# several lines, the way a large project lays out its `api/` subtree.
urlpatterns = [
    re_path(
        r"^api/",
        include(
            [
                re_path(
                    "^ops/",
                    include(
                        [
                            path("run/", RunView.as_view()),
                        ],
                    ),
                ),
                path("open/", OpenView.as_view()),
                path("token/", TokenView.as_view()),
                *router.urls,
            ],
        ),
    ),
    re_path(r"^logo(?:/(?P<filename>.+))?/?$", logo),
]
