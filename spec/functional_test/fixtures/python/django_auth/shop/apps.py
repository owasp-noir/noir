from django.apps import AppConfig
from django.contrib.auth.decorators import login_required
from django.urls import path


class ShopConfig(AppConfig):
    label = "shop"
    name = "shop"

    def ready(self):
        from shop import views

        self.summary_view = views.SummaryView
        self.saved_view = views.SavedView

    def get_urls(self):
        urls = [
            path("", self.summary_view.as_view(), name="summary"),
            path("saved/", login_required(self.saved_view.as_view()), name="saved"),
        ]
        return urls
