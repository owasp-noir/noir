"""Root urlconf that builds most of `urlpatterns` at import time.

This is the shape that used to make the whole tree invisible: the
ROOT_URLCONF anchor resolves and yields a *non-empty* result (the two
literal `path()` entries below), so the orphan-urlconf pass was skipped
and every app urlconf mounted through the loop was never read.
"""

from django.urls import include, path

from apps.registry import mounted_apps
from project.views import health

_dynamic = []

for _app in mounted_apps():
    for module, mountpoint in _app.mountpoints.items():
        _dynamic.append(path(mountpoint, include((module, _app.label))))

urlpatterns = [
    path("", include(_dynamic)),
    path("-/health/", health),
    path("billing/", include("apps.billing.urls")),
]
