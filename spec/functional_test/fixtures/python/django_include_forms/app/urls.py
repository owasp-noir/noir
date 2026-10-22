from django.urls import path
from . import views

urlpatterns = [
    path('x/<int:pk>/', views.x),
]
