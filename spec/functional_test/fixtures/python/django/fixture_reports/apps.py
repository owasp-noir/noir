from django.urls import path

from blog import views


class FixtureReportsConfig:
    label = "fixture_reports"
    name = "fixture_reports"

    def get_urls(self):
        urlpatterns = [
            path("daily/", views.shop_daily_report, name="shop-daily-report"),
        ]
        return self.post_process_urls(urlpatterns)
