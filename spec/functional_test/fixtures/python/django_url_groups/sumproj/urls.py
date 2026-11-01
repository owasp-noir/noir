from django.urls import path

from proj.views import home

part_a = [path("summed/a/", home)]
part_b = [path("summed/b/", home)]
parts = [part_a]
parts += [part_b]

urlpatterns = sum(parts, [])
