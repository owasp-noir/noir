from django.urls import re_path

from . import views

urlpatterns = [
    # Django's idiom for "the trailing slash is optional". The `?` is a
    # regex quantifier on the preceding `/`, not a path character.
    re_path(r'^tags/?$', views.tags),
    re_path(r'^search/?$', views.search),
    re_path(r'^articles/(?P<slug>[-\w]+)/comments/?$', views.comments),
    # An optional named group: the parameter stays, the quantifier goes.
    re_path(r'^feed/(?P<page>\d+)?$', views.feed),
]
