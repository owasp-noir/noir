from django.urls import include, path

from blog import views

# A `urls/` package whose `__init__.py` is the app's urlconf and which
# include()s a sibling module. Exercises the orphan-urlconf fallback's
# prefix nesting and visited-dedup: `dashboard/` must surface as
# `/admin/dashboard/` (mounted under the include prefix), not as a
# second bare `/dashboard/` from processing admin.py as its own root.
urlpatterns = [
    path("posts/", views.posts),
    path("admin/", include("blog.urls.admin")),
]
