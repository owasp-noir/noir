from django.urls import path

from myapp import views

# A reusable Django app ships its own `urls.py` with `urlpatterns`,
# but no project `settings.py` declaring `ROOT_URLCONF`. Noir must
# still surface these routes (app-relative) instead of returning
# nothing.
urlpatterns = [
    path("api/ping/", views.ping),
    path("api/items/", views.items),
    path("api/items/<int:item_id>/", views.item_detail),
]
