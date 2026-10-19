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
        # `views.py` only re-binds this name; the class lives two hops on.
        self.catalogue_view = get_class("fixture_shop.views", "CatalogueView")

    def get_urls(self):
        from allauth.account import views as allauth_views
        from django.contrib.auth import views as auth_views

        urls = [
            path("orders/", views.shop_orders, name="shop-orders"),
            path("reports/", include(self.reports_app.urls[0])),
            path("add/<int:pk>/", self.add_view.as_view(), name="add"),
            path(
                "vouchers/<int:pk>/remove/",
                self.remove_view.as_view(),
                name="vouchers-remove",
            ),
            path("catalogue/", self.catalogue_view.as_view(), name="catalogue"),
            # Django's own view, outside the scan: named, verbs from the table.
            path("password-reset/", auth_views.PasswordResetView.as_view()),
            # Same class name, not Django's: stays an unnamed GET.
            path("login/", allauth_views.LoginView.as_view()),
        ]
        return urls
