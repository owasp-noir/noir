from django.urls import path
from api import views

urlpatterns = [
    path('users/<uuid:id>/', views.user),
]
