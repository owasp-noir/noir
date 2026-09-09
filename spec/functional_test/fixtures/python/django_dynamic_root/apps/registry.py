"""Stand-in for the runtime app registry the root urlconf loops over."""

from django.apps import apps


def mounted_apps():
    return [app for app in apps.get_app_configs() if hasattr(app, "mountpoints")]
