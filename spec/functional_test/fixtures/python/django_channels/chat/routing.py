from channels.auth import AuthMiddlewareStack
from channels.routing import URLRouter
from django.urls import path

from . import consumers, views

lobby_patterns = [
    path("lobby/", consumers.ChatConsumer.as_asgi()),
]

websocket_urlpatterns = [
    path("ws/chat/<str:room_name>/", consumers.ChatConsumer.as_asgi()),
    # Nested behind a middleware wrapper: still under "ws/secure/".
    path("ws/secure/", AuthMiddlewareStack(URLRouter(lobby_patterns))),
]

# A plain path() list that is never handed to URLRouter: not a route.
unused_patterns = [
    path("not-mounted/", views.index),
]
