from django.urls import re_path

from notes.consumers import NotesConsumer

# Not mounted by asgi.py: reported app-relative.
websocket_urlpatterns = [
    re_path(r"^ws/notes/$", NotesConsumer.as_asgi()),
]
