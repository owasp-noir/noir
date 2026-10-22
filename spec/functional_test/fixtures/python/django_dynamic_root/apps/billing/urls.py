from django.urls import path

from apps.billing import views

# Reached by a literal `include()` from the root urlconf, so these must
# appear once under the `billing/` mount prefix - never a second time
# app-relative as `/invoices/`.
urlpatterns = [
    path("invoices/", views.invoices),
]
