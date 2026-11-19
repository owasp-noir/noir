require "../../func_spec.cr"

# `[FromQuery] ProductQuery query` binds the type's members (inherited ones
# included) from the query string, each under its `[FromQuery(Name)]` if it
# has one; there is no `query` parameter.
query_params = [
  Param.new("Term", "", "query"), Param.new("sort_by", "", "query"), Param.new("MinPrice", "", "query"),
  Param.new("Page", "", "query"), Param.new("PageSize", "", "query"),
]
expected_endpoints = [
  Endpoint.new("/api/products", "GET", query_params),
  Endpoint.new("/api/products/export", "GET", query_params + [Param.new("format", "", "query")]),
  Endpoint.new("/api/products", "POST", [Param.new("name", "", "json"), Param.new("price", "", "json")]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_query_models/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC [FromQuery] complex types", tags: "functional" do
  it "reports the members, not the argument" do
    names = tester.app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/products" }.params.map(&.name)
    names.sort!.should eq(["MinPrice", "Page", "PageSize", "Term", "sort_by"])
  end
end
