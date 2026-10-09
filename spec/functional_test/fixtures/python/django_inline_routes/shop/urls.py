from django.urls import include, path, re_path

from . import views

# Several sibling routes on one source line.
urlpatterns = [path('', views.home), path('about/', views.about), path('items/<int:pk>/', views.item)]

# An inline include() whose body is one line of sibling routes.
urlpatterns += [
    path('api/', include([path('users/', views.users), re_path(r'^teams/$', views.teams), path('ping/', views.ping)])),
]

# Comments are not code: no route for the commented-out call, and a `(`
# in a trailing comment does not keep the call open.
urlpatterns += [
    path('kept/', views.home),  # was: path('old/', views.about)
    path('split/',  # see (
         views.about),
]
