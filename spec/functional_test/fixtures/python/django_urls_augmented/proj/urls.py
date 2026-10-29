from django.conf.urls.i18n import i18n_patterns
from django.urls import URLPattern, URLResolver, include, path

from proj.rest import rest_path
from proj.views import get_me, health, login_page, update_me

v1_api_patterns = [
    rest_path("users/me", GET=get_me, PATCH=update_me),
    path("users/me/plain", get_me),
]

i18n_urls = [
    path("login/", login_page),
]

urls: list[URLPattern | URLResolver] = list(i18n_urls)
urls += [
    path("api/v1/", include(v1_api_patterns)),
]
urls += [path("health", health)]

urlpatterns = i18n_patterns(*i18n_urls) + urls
