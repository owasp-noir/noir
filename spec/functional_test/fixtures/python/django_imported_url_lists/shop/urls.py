from django.urls import include, re_path

import shop.control.urls
from shop import views
from shop.legacy.urls import urlpatterns as legacy_patterns
from shop.parts import ev, part

base_patterns = [
    re_path(r'^healthcheck/$', views.health, name='healthcheck'),
    re_path(r'^api/v1/', include(('shop.api.urls', 'api'), namespace='api-v1')),
    # A urlconf's own `urlpatterns`, imported under another name.
    re_path(r'^legacy/', include(legacy_patterns)),
    re_path(r'^one/', include(part)),
    re_path(r'^two/', include(part)),
    re_path(r'^none/', include(ev)),
]

control_patterns = [
    re_path(r'^control/', include((shop.control.urls, 'control'))),
]

common_patterns = base_patterns + control_patterns
