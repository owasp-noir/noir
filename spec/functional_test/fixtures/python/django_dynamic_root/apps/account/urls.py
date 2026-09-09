from django.urls import path

from apps.account import views

# Mounted only through the dynamic loop in project/urls.py, so the
# analyzer cannot recover the prefix. The routes are still real and must
# be reported app-relative rather than dropped.
urlpatterns = [
    path("profile/", views.profile),
    path("tokens/", views.tokens),
    path("tokens/<uuid:pk>/", views.token_detail),
]
