require "../../func_spec.cr"

# A stock create/update left to DRF's mixins (`ModelViewSet`, generic views)
# validates `self.get_serializer(data=request.data)`, so the body is the
# view's `serializer_class` fields: declared ones, or a literal `Meta.fields`
# list minus `read_only_fields`, the pk and a hyperlinked serializer's `url`.
pk = Param.new("pk", "", "path")
snippet = %w[title code linenos].map { |name| Param.new(name, "", "form") }
user = %w[username email groups].map { |name| Param.new(name, "", "form") }
group = [Param.new("name", "", "form")]
expected_endpoints = [
  Endpoint.new("/snippets/", "GET"),
  Endpoint.new("/snippets/", "POST", snippet),
  Endpoint.new("/snippets/{pk}/", "GET", [pk]),
  Endpoint.new("/snippets/{pk}/", "PUT", snippet + [pk]),
  Endpoint.new("/snippets/{pk}/", "PATCH", snippet + [pk]),
  Endpoint.new("/snippets/{pk}/", "DELETE", [pk]),
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/", "POST", user),
  Endpoint.new("/users/{pk}/", "GET", [pk]),
  Endpoint.new("/users/{pk}/", "PUT", user + [pk]),
  Endpoint.new("/users/{pk}/", "PATCH", user + [pk]),
  Endpoint.new("/users/{pk}/", "DELETE", [pk]),
  Endpoint.new("/snippet-create/", "GET"),
  Endpoint.new("/snippet-create/", "POST", snippet),
  Endpoint.new("/group-update/<int:pk>/", "PUT", group + [pk]),
  Endpoint.new("/group-update/<int:pk>/", "PATCH", group + [pk]),
  Endpoint.new("/snippet-explicit/", "POST", snippet),
]

FunctionalTester.new("fixtures/python/django_drf_stock_actions/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
