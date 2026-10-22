from channels.routing import URLRouter
from django.urls import path, re_path

from notes.consumers import NotesConsumer

# Not mounted by asgi.py: reported app-relative.
websocket_urlpatterns = [
    re_path(r"^ws/notes/$", NotesConsumer.as_asgi()),
    # A list that mounts itself is not expanded into itself again.
    path("x/", URLRouter(websocket_urlpatterns)),
]
