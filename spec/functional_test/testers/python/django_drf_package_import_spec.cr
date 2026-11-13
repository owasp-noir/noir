require "../../func_spec.cr"

# Regression (#3544): `router.register(prefix, ViewSet)` emitted nothing,
# with no warning, for two common import shapes in the urlconf.
#
# `from app.api.views import WidgetViewSet` names a package, and the package
# map only records a file for a module, so a ViewSet re-exported by the
# package's `__init__.py` (or defined in it, `LegacyViewSet`) never resolved.
# urlconf views already followed the imports in that case; `register()` now
# does too.
#
# `from app.api.views.item_viewset import ItemViewSet, \` dropped every name
# after the backslash (`GadgetViewSet`), because the import parser read one
# physical line at a time. The same went for the alias map an imported
# router is looked up through (`router as shared_router`).
detail = [Param.new("pk", "", "path")]
extracted_endpoints = %w[widgets items gadgets shared/widgets].flat_map do |prefix|
  [
    Endpoint.new("/#{prefix}/", "GET"),
    Endpoint.new("/#{prefix}/", "POST"),
    Endpoint.new("/#{prefix}/{pk}/", "GET", detail),
    Endpoint.new("/#{prefix}/{pk}/", "PUT", detail),
    Endpoint.new("/#{prefix}/{pk}/", "PATCH", detail),
    Endpoint.new("/#{prefix}/{pk}/", "DELETE", detail),
  ]
end
# ReadOnlyModelViewSet: list and retrieve only.
extracted_endpoints << Endpoint.new("/legacy/", "GET")
extracted_endpoints << Endpoint.new("/legacy/{pk}/", "GET", detail)

FunctionalTester.new("fixtures/python/django_drf_package_import/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints).perform_tests
