require "../../func_spec.cr"

# Regression (#3294): query params a viewset reads in `get_queryset()`.
# `ArticleViewSet.list` calls it nested in another self call
# (`self.paginate_queryset(self.get_queryset())`); `TagViewSet` leaves
# `list` / `retrieve` to DRF's mixins, whose bodies call it (`retrieve`
# through `get_object()`), and `StatusViewSet.list` hands back to it with
# `super().list(...)`. `create` does not read the queryset.
expected_endpoints = [
  Endpoint.new("/api/articles", "GET", [Param.new("author", "", "query")]),
  Endpoint.new("/api/tags", "GET", [Param.new("tag", "", "query")]),
  Endpoint.new("/api/tags", "POST"),
  Endpoint.new("/api/tags/{pk}", "GET", [Param.new("tag", "", "query"), Param.new("pk", "", "path")]),
  Endpoint.new("/api/statuses", "GET", [Param.new("status", "", "query")]),
]

FunctionalTester.new("fixtures/python/django_drf_get_queryset/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "DRF mixin create negatives", tags: "functional" do
  it "does not give a mixin create the queryset's query params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/django_drf_get_queryset/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoint = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/api/tags" }
    endpoint.params.should be_empty
  end
end
