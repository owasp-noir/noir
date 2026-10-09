from django.urls import path, include

urlpatterns = [
    # A package urlconf (api/urls/__init__.py) and the (module, app_name)
    # tuple form both mount under their prefix.
    path('api/', include('api.urls')),
    path('v1/', include(('app.urls', 'app'), namespace='app')),
]
