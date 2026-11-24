INSTALLED_APPS = ["django.contrib.auth", "rest_framework", "shop.orders"]
ROOT_URLCONF = "shop.urls"
REST_FRAMEWORK = {
    "DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.IsAuthenticated"],
}
