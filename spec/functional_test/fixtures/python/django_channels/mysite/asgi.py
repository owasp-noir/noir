import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from django.core.asgi import get_asgi_application
from django.urls import path, re_path

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "mysite.settings")
django_asgi_app = get_asgi_application()

import chat.routing  # noqa: E402
from chat.consumers import LiveConsumer  # noqa: E402
from game.routing import game_patterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": AllowedHostsOriginValidator(
            AuthMiddlewareStack(
                URLRouter(
                    chat.routing.websocket_urlpatterns
                    + [
                        path("game/", URLRouter(game_patterns)),
                        re_path(r"^live/(?P<feed>\w+)/$", LiveConsumer.as_asgi()),
                    ]
                )
            )
        ),
    }
)
