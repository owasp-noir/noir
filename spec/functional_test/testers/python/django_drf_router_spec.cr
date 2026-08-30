require "../../func_spec.cr"

# Regression: a Django REST Framework app module that names `django` nowhere.
#
# `catalog/urls.py` builds a router and assigns `urlpatterns = router.urls`;
# `catalog/views.py` subclasses `rest_framework` viewsets. Neither imports
# `django`, because DRF supplies everything the module needs — and this is the
# canonical shape of an app-level `urls.py` in a REST project, not a corner
# case. The Django *detector* only looked for `django` imports, so nothing was
# detected here, the analyzer never ran, and the whole REST surface read as
# zero endpoints even though `extract_drf_direct_router_endpoints` had handled
# `urlpatterns = router.urls` all along.
#
# The router is `BulkRouter`, a `DefaultRouter` subclass imported from
# `myproject.api.routers` — a package that does not exist in this fixture, on
# purpose. Subclassing the router to add bulk operations or a custom root view
# is standard practice (NetBox ships `NetBoxRouter`), and the subclass usually
# lives in another package the scan may not even cover. Router recognition is
# therefore keyed on the `<name>.register(prefix, viewset)` call, never on the
# constructor's class: an unresolvable base class must not cost us the routes.
# The false-positive risk that buys is already contained downstream — a
# `register()` on something that isn't a DRF router resolves to no ViewSet and
# emits nothing.
extracted_endpoints = [
  # ModelViewSet -> the full REST set, plus the @action detail route.
  Endpoint.new("/widgets/", "GET"),
  Endpoint.new("/widgets/", "POST"),
  Endpoint.new("/widgets/{pk}/", "GET", [Param.new("pk", "", "path")]),
  Endpoint.new("/widgets/{pk}/", "PUT", [Param.new("pk", "", "path")]),
  Endpoint.new("/widgets/{pk}/", "PATCH", [Param.new("pk", "", "path")]),
  Endpoint.new("/widgets/{pk}/", "DELETE", [Param.new("pk", "", "path")]),
  Endpoint.new("/widgets/{pk}/activate/", "POST", [
    Param.new("reason", "", "form"),
    Param.new("pk", "", "path"),
  ]),
  # ReadOnlyModelViewSet -> list + retrieve only, keyed by lookup_url_kwarg.
  Endpoint.new("/gadgets/", "GET", [Param.new("kind", "", "query")]),
  Endpoint.new("/gadgets/{gadget_id}/", "GET", [Param.new("gadget_id", "", "path")]),
]

FunctionalTester.new("fixtures/python/django_drf_router/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
