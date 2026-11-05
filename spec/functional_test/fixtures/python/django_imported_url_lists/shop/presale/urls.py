from django.urls import re_path

from shop import views

event_patterns = [
    re_path(r'^$', views.event_index, name='event.index'),
]

organizer_patterns = [
    re_path(r'^$', views.organizer_index, name='organizer.index'),
]

locale_patterns = [
    re_path(r'^locale/set$', views.locale_set, name='locale.set'),
]

# Imported by nobody: not served.
unused_patterns = [
    re_path(r'^unused/$', views.health),
]
