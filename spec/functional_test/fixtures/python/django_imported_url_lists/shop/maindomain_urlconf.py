# pretix's root urlconf: `urlpatterns` concatenates lists imported from
# other urlconfs, and an include() concatenates imported lists with an
# inline one.
from django.urls import include, re_path

from shop.presale.urls import event_patterns, locale_patterns, organizer_patterns
from shop.urls import common_patterns

presale_patterns_main = [
    re_path(r'', include((locale_patterns + [
        re_path(r'^(?P<organizer>[^/]+)/', include(organizer_patterns)),
        re_path(r'^(?P<organizer>[^/]+)/(?P<event>[^/]+)/', include(event_patterns)),
    ], 'presale')))
]

urlpatterns = common_patterns + presale_patterns_main
