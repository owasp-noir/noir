from django.urls import path, include

from . import views

urlpatterns = [path("health/", views.health)]

# Rebinding urlpatterns to a list that includes its previous value.
urlpatterns = [path("v1/", include(urlpatterns))]

# Mutually recursive local lists must not loop either.
ping = [path("ping/", include(pong))]
pong = [path("pong/", include(ping))]
urlpatterns += [path("loop/", include(ping))]
