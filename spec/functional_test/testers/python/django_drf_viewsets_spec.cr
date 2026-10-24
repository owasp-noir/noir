require "../../func_spec.cr"

# DRF routes as DRF builds them:
# - `*router.urls` unpacked into an inline `include([...])` whose call wraps
#   over many lines mounts the router under the include's prefix, and the
#   nested include's entries are not re-read at the root;
# - a ViewSet gets the standard actions its mixins provide anywhere up its
#   in-project inheritance chain, the `@action`s and overrides its bases
#   define, and a `@x.mapping.<verb>` extra verb on an action's route;
# - `@action` `url_path` defaults to the method name (underscores kept) and
#   a regex `url_path` keeps its named groups as path params;
# - an APIView serves only the verbs it (or a project base) defines, and
#   `ObtainAuthToken` serves POST;
# - a serializer handed `request.data` contributes its declared fields;
# - an optional non-capturing group in a `re_path` keeps its segment.
pk = Param.new("pk", "", "path")
version_id = Param.new("version_id", "", "path")
extracted_endpoints = [
  Endpoint.new("/api/docs/", "GET"),
  Endpoint.new("/api/docs/{pk}/", "GET", [pk]),
  Endpoint.new("/api/docs/{pk}/", "PUT", [pk]),
  Endpoint.new("/api/docs/{pk}/", "PATCH", [pk]),
  Endpoint.new("/api/docs/{pk}/versions/{version_id}/", "DELETE", [pk, version_id]),
  Endpoint.new("/api/docs/{pk}/versions/{version_id}/", "PATCH", [Param.new("label", "", "form"), pk, version_id]),
  # Body fields come from the serializer handed `request.data`, its project
  # base included; read-only and method fields are not input.
  Endpoint.new("/api/docs/bulk_delete/", "POST", [Param.new("reason", "", "form"), Param.new("ids", "", "form")]),
  Endpoint.new("/api/ops/run/", "POST"),
  Endpoint.new("/api/open/", "GET"),
  Endpoint.new("/api/token/", "POST"),
  Endpoint.new("/logo/{filename}/", "GET", [Param.new("filename", "", "path")]),
]

tester = FunctionalTester.new("fixtures/python/django_drf_viewsets/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints)
tester.perform_tests

describe "Django REST Framework handlers", tags: "functional" do
  handlers = tester.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler} }
  at = ->(key : String) { handlers[key].try { |h| {h.name, h.path.try { |p| File.basename(p) }, h.line} } }

  it "points an action at the method that serves it, wherever in the chain it is defined" do
    at.call("GET /api/docs/").should eq({"DocViewSet.list", "views.py", 42})
    at.call("PUT /api/docs/{pk}/").should eq({"BaseViewSet.update", "views.py", 19})
    at.call("DELETE /api/docs/{pk}/versions/{version_id}/").should eq({"BaseViewSet.delete_version", "views.py", 27})
    at.call("PATCH /api/docs/{pk}/versions/{version_id}/").should eq({"BaseViewSet.rename_version", "views.py", 31})
    at.call("POST /api/docs/bulk_delete/").should eq({"BaseViewSet.bulk_delete", "views.py", 36})
    at.call("POST /api/ops/run/").should eq({"OpsMixin", "views.py", 59})
  end

  it "names no handler for an action DRF itself serves" do
    handlers["GET /api/docs/{pk}/"].should be_nil
    handlers["PATCH /api/docs/{pk}/"].should be_nil
    handlers["POST /api/token/"].should be_nil
  end
end
