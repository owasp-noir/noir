from django.urls import path
from app import views

urlpatterns = [
    path('search/', views.search),
]
