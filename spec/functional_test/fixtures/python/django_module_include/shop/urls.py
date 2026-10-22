from django.urls import path
from shop import views

urlpatterns = [path("cart/", views.cart)]
