require "../../func_spec.cr"

# Conventional routes registered from route-provider classes rather than
# Program.cs: named and positional `MapControllerRoute` calls, interpolated
# templates (`$"{lang}/login/"` with `lang` from a method whose default is
# empty, `{{{RouteValues.SeName}}}` from a constant), the area route, and a
# plugin project whose only routes are pinned templates.
expected_endpoints = [
  # Web: pinned templates next to the Default route.
  Endpoint.new("/login/", "GET"),
  Endpoint.new("/Customer/Login", "GET"),
  Endpoint.new("/login/", "POST", [Param.new("email", "", "form"), Param.new("password", "", "form")]),
  Endpoint.new("/Customer/Login", "POST"),
  Endpoint.new("/customer/addressdelete", "POST", [Param.new("addressId", "", "form")]),
  Endpoint.new("/Customer/AddressDelete", "POST", [Param.new("addressId", "", "form")]),
  Endpoint.new("/orderdetails/pdf/{orderId}", "GET", [Param.new("orderId", "", "path")]),
  Endpoint.new("/Order/GetPdfInvoice", "GET", [Param.new("orderId", "", "query")]),
  Endpoint.new("/{SeName}", "GET", [Param.new("SeName", "", "path"), Param.new("updatecartitemid", "", "query")]),
  Endpoint.new("/Product/ProductDetails", "GET"),
  # Admin area: only the area route reaches it.
  Endpoint.new("/Admin/Category/List", "GET"),
  Endpoint.new("/Admin/Category/Edit/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Admin/Customer/AddressDelete/{id}", "POST", [Param.new("customerId", "", "form"), Param.new("id", "", "path")]),
  # Plugin: its pinned templates, plus the default and area routes of the
  # host it is mounted into.
  Endpoint.new("/news", "GET"),
  Endpoint.new("/News/List", "GET"),
  Endpoint.new("/news/rss/{languageId}", "GET", [Param.new("languageId", "", "path")]),
  Endpoint.new("/News/ListRss", "GET"),
  Endpoint.new("/Admin/News/Edit/{id?}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Admin/NewsAdmin/NewsItemEdit/{id}", "GET"),
  Endpoint.new("/Admin/NewsAdmin/Delete/{id}", "POST"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_route_provider/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC route providers and areas", tags: "functional" do
  it "keeps area controllers off the area-less routes" do
    urls = tester.app.endpoints.map(&.url)
    urls.includes?("/Category/Edit/{id}").should be_false
    urls.includes?("/Customer/AddressDelete/{id}").should be_false
  end

  it "does not hand a pinned template to an area controller of the same name" do
    tester.app.endpoints.select { |e| e.url == "/customer/addressdelete" }.map(&.handler.try(&.path)).all?(&.try(&.includes?("/Web/Controllers/"))).should be_true
  end

  it "skips a template it cannot read" do
    tester.app.endpoints.any? { |e| e.url.includes?("Routes") || e.url.includes?("Configuration") }.should be_false
  end
end
