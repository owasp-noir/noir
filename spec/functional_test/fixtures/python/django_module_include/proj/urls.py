from django.urls import include, path
import shop.urls

# `include()` takes the urlconf module object itself, not only its dotted
# name; `shop.urls` here is a module, not a DRF router's url list.
urlpatterns = [
    path("shop/", include(shop.urls)),
]
