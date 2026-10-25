require "../../func_spec.cr"

# DRF routes a project router and its viewsets add:
# - a router class that extends DRF's route table
#   (`self.routes[0].mapping.update({"delete": "bulk_destroy"})`) serves the
#   verb on the list route when the viewset has the method (`bulk_destroy`
#   on a mixin), and not when it lacks it (`bulk_update`);
# - a viewset method named after a verb (`def patch`) serves that verb on
#   the routes the viewset has;
# - a serializer bound to `request.data` names the body of a DELETE too,
#   `get_serializer` resolves `serializer_class` where the viewset declares
#   it, and a `self` helper handed `request` adds the header it reads;
# - a `get_serializer_class` override choosing by `self.action` decides the
#   serializer of that action;
# - a verb method needing a kwarg the route does not pass
#   (`def delete(self, request, key)` on the list route) is not routed.
pk = Param.new("pk", "", "path")
note = Param.new("note", "", "form")
extracted_endpoints = [
  Endpoint.new("/tags/", "GET"),
  Endpoint.new("/tags/", "POST"),
  Endpoint.new("/tags/", "DELETE", [note]),
  Endpoint.new("/tags/{pk}/", "GET", [pk]),
  Endpoint.new("/tags/{pk}/", "PUT", [Param.new("if-match", "", "header"), Param.new("name", "", "form"), pk]),
  Endpoint.new("/tags/{pk}/", "PATCH", [pk]),
  Endpoint.new("/tags/{pk}/", "DELETE", [note, pk]),
  Endpoint.new("/notes/", "GET"),
  Endpoint.new("/notes/", "POST"),
  Endpoint.new("/notes/", "DELETE", [note]),
  Endpoint.new("/notes/{pk}/", "GET", [pk]),
  Endpoint.new("/notes/{pk}/", "PUT", [Param.new("if-match", "", "header"), note, pk]),
  Endpoint.new("/notes/{pk}/", "PATCH", [pk]),
  Endpoint.new("/notes/{pk}/", "DELETE", [note, pk]),
  Endpoint.new("/config/", "GET"),
  Endpoint.new("/config/", "PATCH", [Param.new("theme", "", "form")]),
]

tester = FunctionalTester.new("fixtures/python/django_drf_bulk_router/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints)
tester.perform_tests

describe "DRF router-added routes", tags: "functional" do
  handlers = tester.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler} }
  at = ->(key : String) { handlers[key].try { |h| {h.name, h.path.try { |p| File.basename(p) }, h.line} } }

  it "names the method the router maps the verb to" do
    at.call("DELETE /tags/").should eq({"BulkDestroyMixin.bulk_destroy", "base.py", 7})
    at.call("PATCH /config/").should eq({"ConfigViewSet.patch", "views.py", 24})
  end

  it "keeps the viewset among an inherited action's code" do
    ep = tester.endpoints.find! { |e| e.method == "DELETE" && e.url == "/tags/" }
    ep.details.code_paths.any?(&.path.ends_with?("api/views.py")).should be_true
  end
end
