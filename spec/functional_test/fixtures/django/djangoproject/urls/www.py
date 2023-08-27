from django.urls import include, path
from django.views.generic import RedirectView, TemplateView

urlpatterns = [
    path(
        "start/overview/",
        TemplateView.as_view(template_name="overview.html"),
        name="overview",
    ),
    path("overview/", RedirectView.as_view(url="/start/overview/", permanent=False)),
    # include
    path("accounts/", include("accounts.urls")),
]
