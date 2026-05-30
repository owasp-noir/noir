from django.urls import include, path

from . import views

urlpatterns = [
    path(route='keyword-route/', view=views.keyword_route, name='keyword_route'),
    path('inline/', include([
        path('nested/', views.inline_nested, name='inline_nested'),
    ])),
]
