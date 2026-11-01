require "../../func_spec.cr"

# drf-extensions' NestedRouterMixin (Read the Docs' API v3): the item
# `router.register(...)` returns registers children under the parent's
# prefix and a `parent_lookup_<lookup>` segment per level, on the root
# router. A commented-out nested registration routes nothing, and a plain
# `router.register` is unchanged.
FunctionalTester.new("fixtures/python/django_drf_nested_router/", {
  :techs     => 1,
  :endpoints => 4,
}, [
  Endpoint.new("/projects/", "GET"),
  Endpoint.new("/projects/{parent_lookup_project__slug}/versions/{slug}/", "GET", [
    Param.new("parent_lookup_project__slug", "", "path"),
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/projects/{parent_lookup_project__slug}/versions/{parent_lookup_version__slug}/builds/", "GET", [
    Param.new("parent_lookup_version__slug", "", "path"),
  ]),
  Endpoint.new("/remote/", "GET"),
]).perform_tests
