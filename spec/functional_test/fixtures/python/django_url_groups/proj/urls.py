from functools import reduce
from operator import add

from django.conf import settings
from django.urls import include, path

from proj.views import debug_page, extension, home, search

basic_urls = [
    path("", home),
]

app_urls = [
    path("search/", search),
    path("dashboard/", include("dash.urls")),
]

debug_urls = [path("debug/", debug_page)]

# a list that is never added to `groups`
unused_urls = [path("unused/", home)]
# groups.append(unused_urls)
other_groups = [unused_urls]
other_groups.append(unused_urls)

groups = [
    basic_urls,
    app_urls,
]

if settings.DEBUG:
    groups.insert(0, debug_urls)

if getattr(settings, "EXTENSIONS", False):
    groups.append([path("ext/", extension)])

urlpatterns = reduce(add, groups)
