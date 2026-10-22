require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/Open/Callback/{appId}", "GET", [
    Param.new("appId", "", "path"),
  ]),
  Endpoint.new("/data/default", "GET"),
  Endpoint.new("/account/login", "GET"),
  Endpoint.new("/User/Details", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/User/Search", "GET", [
    Param.new("query", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/User/Create", "POST", [
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
  ]),
  Endpoint.new("/User/Update", "PUT", [
    Param.new("id", "", "form"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/User/Delete", "DELETE", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/Product/List", "GET", [
    Param.new("categoryId", "", "query"),
    Param.new("sortBy", "", "query"),
  ]),
  Endpoint.new("/Product/Add", "POST", [
    Param.new("productName", "", "form"),
    Param.new("price", "", "form"),
    Param.new("stock", "", "form"),
  ]),
  Endpoint.new("/Product/Show", "GET", [
    Param.new("productId", "", "query"),
  ]),
  # New ApiController endpoints with attribute-based routing
  Endpoint.new("/api/Api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/Api/users", "POST", [
    Param.new("userData", "", "json"),
    Param.new("apiKey", "", "header"),
  ]),
  Endpoint.new("/api/Api/products/{productId}", "PUT", [
    Param.new("productId", "", "path"),
    Param.new("productData", "", "json"),
    Param.new("contentType", "", "header"),
  ]),
  Endpoint.new("/api/Api/items/{itemId}", "DELETE", [
    Param.new("itemId", "", "path"),
    Param.new("confirm", "", "query"),
    Param.new("authorization", "", "header"),
  ]),
  Endpoint.new("/api/Api/search", "GET", [
    Param.new("term", "", "query"),
    Param.new("page", "", "query"),
    Param.new("acceptLanguage", "", "header"),
  ]),
  Endpoint.new("/api/Api/upload", "POST", [
    Param.new("fileName", "", "form"),
    Param.new("description", "", "form"),
    Param.new("contentType", "", "header"),
  ]),
  Endpoint.new("/api/Api/profile", "GET", [
    Param.new("sessionId", "", "cookie"),
    Param.new("preferences", "", "cookie"),
  ]),
  Endpoint.new("/rooted/ping", "GET"),
  # Several controllers in one file, each on a local base class.
  Endpoint.new("/First/Index", "GET"),
  Endpoint.new("/First/Data", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/First/Download", "GET", [
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/First/Save", "POST", [
    Param.new("id", "", "form"),
    Param.new("continueEditing", "", "form"),
  ]),
  Endpoint.new("/Fourth/Visible", "GET"),
  Endpoint.new("/second/other", "GET", [
    Param.new("x", "", "query"),
  ]),
  Endpoint.new("/Third/Third", "GET", [
    Param.new("x", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_mvc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET MVC controller discovery", tags: "functional" do
  it "names a parameter, not its default value or a trailing comment" do
    save = tester.app.endpoints.find! { |e| e.url == "/First/Save" }
    save.params.map(&.name).should eq ["id", "continueEditing"]
  end

  it "leaves Web API / OData controllers alone" do
    tester.app.endpoints.any?(&.url.starts_with?("/Items")).should be_false
    tester.app.endpoints.any?(&.url.starts_with?("/LegacyApi")).should be_false
  end

  it "skips non-routable classes and non-action methods" do
    urls = tester.app.endpoints.map(&.url)
    %w[/SharedBase/Shared /Generic/List /Cache/Bogus /Fourth/Helper /Fourth/Menu
      /Fourth/Stat /Fourth/Priv /Fourth/Raw].each do |url|
      urls.should_not contain(url)
    end
  end
end
