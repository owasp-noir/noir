from channels.routing import URLRouter
from django.urls import path

from game.consumers import LobbyConsumer, PlayConsumer

game_patterns = [
    path("play/<int:match_id>/", PlayConsumer.as_asgi()),
    path("lobby/", URLRouter([
        path("chat/", LobbyConsumer.as_asgi()),
    ])),
]
