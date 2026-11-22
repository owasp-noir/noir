require "../../func_spec.cr"

# A stock create/update left to DRF's mixins (`ModelViewSet`, generic views)
# validates `self.get_serializer(data=request.data)`, so the body is the
# view's `serializer_class` fields: declared ones, or a literal `Meta.fields`
# list minus `read_only_fields`, the pk and a hyperlinked serializer's `url`.
pk = Param.new("pk", "", "path")
snippet = %w[title code linenos].map { |name| Param.new(name, "", "form") }
user = %w[username email groups].map { |name| Param.new(name, "", "form") }
group = %w[name labels labels.value capacity].map { |name| Param.new(name, "", "form") }
user_filters = %w[term sort is_active].map { |name| Param.new(name, "", "query") }
pages = %w[number count].map { |name| Param.new(name, "", "query") }
expected_endpoints = [
  Endpoint.new("/snippets/", "GET", %w[limit offset].map { |name| Param.new(name, "", "query") }),
  Endpoint.new("/snippets/feed/", "GET", [Param.new("cursor", "", "query"), Param.new("term", "", "query")]),
  Endpoint.new("/snippets/summary/", "GET"),
  Endpoint.new("/snippets/import_labels/", "POST", %w[name labels labels.value].map { |name| Param.new(name, "", "form") }),
  Endpoint.new("/snippets/", "POST", snippet),
  Endpoint.new("/snippets/{pk}/", "GET", [pk]),
  Endpoint.new("/snippets/{pk}/", "PUT", snippet + [pk]),
  Endpoint.new("/snippets/{pk}/", "PATCH", snippet + [pk]),
  Endpoint.new("/snippets/{pk}/", "DELETE", [pk]),
  Endpoint.new("/users/", "GET", pages + user_filters),
  Endpoint.new("/users/", "POST", user),
  Endpoint.new("/users/{pk}/", "GET", user_filters + [pk]),
  Endpoint.new("/users/{pk}/", "PUT", user + user_filters + [pk]),
  Endpoint.new("/users/{pk}/", "PATCH", user + user_filters + [pk]),
  Endpoint.new("/users/{pk}/", "DELETE", user_filters + [pk]),
  Endpoint.new("/snippet-create/", "GET", %w[nickname name name__startswith].map { |name| Param.new(name, "", "query") }),
  Endpoint.new("/snippet-create/", "POST", snippet),
  Endpoint.new("/group-update/<int:pk>/", "PUT", group + [pk]),
  Endpoint.new("/group-update/<int:pk>/", "PATCH", group + [pk]),
  Endpoint.new("/snippet-explicit/", "POST", snippet),
]

tester = FunctionalTester.new("fixtures/python/django_drf_stock_actions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "marks fields from a runtime-selected serializer as conditional", tags: "functional" do
  endpoint = tester.endpoints.find! { |ep| ep.method == "PUT" && ep.url.includes?("group-update") }
  endpoint.params.find!(&.name.==("labels.value")).tags.map(&.name).should contain("conditional")
end

it "retains the configured query names when a runtime override is unresolved", tags: "functional" do
  endpoint = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/users/" }
  %w[sort count].each do |name|
    endpoint.params.find!(&.name.==(name)).tags.map(&.name).should contain("conditional")
  end
end
