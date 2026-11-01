require "../../func_spec.cr"

# DRF 2.x / Taiga extra actions: `@list_route(...)` is `@action(detail=False)`,
# `@detail_route(...)` is `@action(detail=True)`, inherited from a mixin
# too; no `methods=` means GET and `url_path=` names the segment.
# `request.QUERY_PARAMS` / `request.DATA` are DRF 2.x's `query_params` /
# `data`. A commented-out decorator routes nothing, and a `self.lookup_field`
# set inside an action does not rename the detail route's `{pk}`.
FunctionalTester.new("fixtures/python/django_drf_legacy_routes/", {
  :techs     => 1,
  :endpoints => 12,
}, [
  Endpoint.new("/issues/filters_data", "GET", [Param.new("project", "", "query")]),
  Endpoint.new("/issues/bulk-create", "POST", [Param.new("bulk_issues", "", "form")]),
  Endpoint.new("/issues/by_ref", "GET"),
  Endpoint.new("/issues/{pk}/upvote", "POST", [Param.new("pk", "", "path")]),
  Endpoint.new("/issues/{pk}/history", "GET"),
  Endpoint.new("/issues/{pk}/history", "PUT"),
  Endpoint.new("/issues", "GET"),
  Endpoint.new("/issues/{pk}", "DELETE"),
  Endpoint.new("/issues/{pk}", "GET", [Param.new("pk", "", "path")]),
]).perform_tests
