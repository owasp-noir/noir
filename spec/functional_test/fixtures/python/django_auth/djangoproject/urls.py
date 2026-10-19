from django.apps import apps
from django.contrib import admin
from django.contrib.auth.decorators import login_required
from django.urls import include, path
from django.views.decorators.csrf import csrf_exempt
from blog import views

urlpatterns = [
    path('admin/', admin.site.urls),
    path('posts/', views.post_list, name='post_list'),
    path('posts/create/', views.post_create, name='post_create'),
    path('posts/<int:pk>/', views.PostDetailView.as_view(), name='post_detail'),
    path('api/posts/', views.PostAPIView.as_view(), name='post_api'),
    path('public/', views.public_page, name='public_page'),
    path('drafts/', login_required(views.draft_list), name='draft_list'),
    path('export/', csrf_exempt(views.export_page), name='export_page'),
    path('shop/', include(apps.get_app_config('shop').urls[0])),
]
