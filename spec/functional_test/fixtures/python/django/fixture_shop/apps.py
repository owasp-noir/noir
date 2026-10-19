from django.apps import apps
from django.urls import include, path
from oscar.core.loading import get_class

from blog import views


class FixtureShopConfig:
    label = "fixture_shop"
    name = "fixture_shop"

    def ready(self):
        self.reports_app = apps.get_app_config("fixture_reports")
        # Oscar's overridable loader: the module is named app-relative.
        self.add_view = get_class("fixture_shop.views", "BasketAddView")
        self.remove_view = get_class(
            "fixture_shop.views", "VoucherRemoveView"
        )

    def get_urls(self):
        urls = [
            path("orders/", views.shop_orders, name="shop-orders"),
            path("reports/", include(self.reports_app.urls[0])),
            path("add/<int:pk>/", self.add_view.as_view(), name="add"),
            path(
                "vouchers/<int:pk>/remove/",
                self.remove_view.as_view(),
                name="vouchers-remove",
            ),
        ]
        return urls
