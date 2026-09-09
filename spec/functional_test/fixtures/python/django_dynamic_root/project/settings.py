"""Project settings. The ROOT_URLCONF here is what anchors the analyzer."""

SECRET_KEY = "spec-only"
DEBUG = False
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "apps.account",
    "apps.billing",
]

ROOT_URLCONF = "project.urls"
