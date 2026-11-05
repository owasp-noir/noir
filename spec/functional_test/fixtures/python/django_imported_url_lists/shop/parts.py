from django.urls import re_path

from shop import views

# Annotated, and mounted twice: served under both prefixes.
part: list = [
    re_path(r'^p/$', views.health),
]

# Not a url list: the include() entry keeps its own reading.
ev = None
