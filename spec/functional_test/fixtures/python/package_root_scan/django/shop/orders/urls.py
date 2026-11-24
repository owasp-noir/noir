from django.urls import path
from shop.orders import views

urlpatterns = [
    path("<int:pk>/", views.detail),
]
