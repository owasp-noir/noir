from django.urls import include, path, re_path

from . import views

# Several sibling routes on one source line.
urlpatterns = [path('', views.home), path('about/', views.about), path('items/<int:pk>/', views.item)]

# An inline include() whose body is one line of sibling routes.
urlpatterns += [
    path('api/', include([path('users/', views.users), re_path(r'^teams/$', views.teams), path('ping/', views.ping)])),
]
