from django.apps import apps
from django.urls import include, path

from blog import views


class FixtureShopConfig:
    label = "fixture_shop"
    name = "fixture_shop"

    def ready(self):
        self.reports_app = apps.get_app_config("fixture_reports")

    def get_urls(self):
        urls = [
            path("orders/", views.shop_orders, name="shop-orders"),
            path("reports/", include(self.reports_app.urls[0])),
        ]
        return urls
