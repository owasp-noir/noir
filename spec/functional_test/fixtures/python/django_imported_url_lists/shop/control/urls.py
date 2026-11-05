from django.urls import re_path

from shop import views

urlpatterns = [
    re_path(r'^event/(?P<organizer>[^/]+)/$', views.event),
]
