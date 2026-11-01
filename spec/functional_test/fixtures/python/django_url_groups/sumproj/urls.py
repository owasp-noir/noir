from django.urls import path

from proj.views import home

DEBUG = False

part_a = [path("summed/a/", home)]
part_b = [path("summed/b/", home)]
part_c = [path("summed/c/", home)]
part_d = [path("summed/d/", home)]
stale = [path("summed/stale/", home)]

parts = [stale]
parts = [
    part_a,  # first
    part_b,
]  # rebound: `stale` is no longer a member
parts += [part_c if DEBUG else part_d]

urlpatterns = sum(parts, [])
