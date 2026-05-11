from django.urls import path

from . import views

urlpatterns = [
    path('users', views.create_user, name='create_user'),
    path('profile', views.ProfileView.as_view(), name='profile'),
]
