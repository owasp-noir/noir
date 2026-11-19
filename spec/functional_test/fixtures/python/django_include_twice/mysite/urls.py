from django.urls import include, path

# Django docs, "URL namespaces": two instances of the same app.
urlpatterns = [
    path("author-polls/", include("polls.urls", namespace="author-polls")),
    path("publisher-polls/", include("polls.urls", namespace="publisher-polls")),
    # API versioning with one urlconf.
    path("api/v1/", include("api.urls")),
    path("api/v2/", include(("api.urls", "api"), namespace="v2")),
]
