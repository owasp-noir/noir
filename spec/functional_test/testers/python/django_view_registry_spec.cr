require "../../func_spec.cr"

# Class-based views as a project builds and serves them:
# - `include(get_model_urls("shop", "item"))` mounts the url list a project
#   function builds from a view registry, which `@register_model_view(...)`
#   decorators fill; both are read by what their bodies do (subscript the
#   registry by the function's parameters, filter on `detail`, route by the
#   entry's `path`), so each decorated view lands under its include;
# - a view named through a package re-export (`from .misc import *`), and a
#   base class reached through one (`generic.ObjectView`), resolve;
# - a verb served by a project base's method gets that method as handler,
#   and its params: the `self.form` the view binds (declared fields plus a
#   ModelForm's `Meta.fields`), and what `self` helpers it hands `request`
#   to read;
# - Django's `AuthenticationForm` bound to `request.POST` names its fields,
#   and `data = request.POST if request.method == "POST" else request.GET`
#   reads the mapping of the verb served;
# - a helper the view overrides is the one its inherited handler runs, and
#   of two `import *` binding a name the last wins;
# - a model in `shop/models/models.py` still has app label `shop`, and a
#   model re-exported from a module named like it (`order.py` -> `Order`)
#   binds the class, not the module, on a case-insensitive file system.
pk = Param.new("pk", "", "path")
edit_form = [Param.new("return_url", "", "query"), Param.new("note", "", "form"), Param.new("name", "", "form"), Param.new("price", "", "form")]
extracted_endpoints = [
  Endpoint.new("/shop/items/", "GET", [Param.new("per_page", "", "query")]),
  Endpoint.new("/shop/items/<int:pk>/", "GET", [pk]),
  Endpoint.new("/shop/widgets/", "GET", [Param.new("per_page", "", "query")]),
  Endpoint.new("/shop/orders/", "GET", [Param.new("per_page", "", "query")]),
  Endpoint.new("/shop/items/<int:pk>/edit/", "GET", [pk]),
  Endpoint.new("/shop/items/<int:pk>/edit/", "POST", edit_form + [pk]),
  Endpoint.new("/shop/items/add/", "GET"),
  Endpoint.new("/shop/items/add/", "POST", edit_form),
  Endpoint.new("/login/", "GET", [Param.new("next", "", "query")]),
  Endpoint.new("/login/", "POST", [Param.new("username", "", "form"), Param.new("password", "", "form"), Param.new("next", "", "form")]),
  Endpoint.new("/media/<path:path>", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/override/", "POST", [Param.new("override_field", "", "form")]),
  Endpoint.new("/ping/", "GET", [Param.new("from_helpers", "", "query")]),
]

tester = FunctionalTester.new("fixtures/python/django_view_registry/", {
  :techs     => 1,
  :endpoints => extracted_endpoints.size,
}, extracted_endpoints)
tester.perform_tests

describe "Django registry-built views", tags: "functional" do
  handlers = tester.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep.handler} }
  at = ->(key : String) { handlers[key].try { |h| {h.name, h.path.try { |p| File.basename(p) }, h.line} } }

  it "names the base method serving an inherited verb" do
    at.call("GET /shop/items/<int:pk>/").should eq({"ObjectView", "object_views.py", 17})
    at.call("POST /shop/items/<int:pk>/edit/").should eq({"ObjectEditView", "object_views.py", 27})
    at.call("GET /media/<path:path>").should eq({"MediaView", "misc.py", 21})
    at.call("GET /ping/").should eq({"PingView", "helpers.py", 18})
  end

  it "does not read the overridden helper's params" do
    ep = tester.endpoints.find! { |e| e.method == "POST" && e.url == "/override/" }
    ep.params.map(&.name).should_not contain("base_field")
  end

  it "resolves models declared in models/models.py and order.py" do
    {"/shop/widgets/", "/shop/orders/"}.each do |url|
      ep = tester.endpoints.find! { |e| e.method == "GET" && e.url == url }
      ep.details.code_paths.any?(&.path.ends_with?("shop/views.py")).should be_true
    end
  end

  it "keeps the decorated view class among the endpoint's code" do
    ep = tester.endpoints.find! { |e| e.method == "GET" && e.url == "/shop/items/<int:pk>/" }
    ep.details.code_paths.any?(&.path.ends_with?("shop/views.py")).should be_true
  end
end
