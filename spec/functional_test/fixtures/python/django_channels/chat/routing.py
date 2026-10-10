from django.urls import path

from . import consumers, views

websocket_urlpatterns = [
    path("ws/chat/<str:room_name>/", consumers.ChatConsumer.as_asgi()),
]

# A plain path() list that is never handed to URLRouter: not a route.
unused_patterns = [
    path("not-mounted/", views.index),
]
