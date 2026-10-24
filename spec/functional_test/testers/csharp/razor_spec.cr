require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("Search", "", "query"),
  ]),
  Endpoint.new("/users", "POST", [
    Param.new("user_name", "", "form"),
    Param.new("handler", "Delete", "query"),
    Param.new("id", "", "form"),
    Param.new("Search", "", "form"),
  ]),
  Endpoint.new("/Orders", "GET", [
    Param.new("handler", "Stats", "query"),
  ]),
  Endpoint.new("/Orders", "POST", [
    Param.new("handler", "Archive", "query"),
    Param.new("X-Token", "", "header"),
    Param.new("limit", "", "query"),
    Param.new("Note", "", "form"),
  ]),
  Endpoint.new("/Users/Edit/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/Users/Edit/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("Input", "", "form"),
  ]),
  Endpoint.new("/Admin/Reports/{year}", "GET", [
    Param.new("year", "", "path"),
  ]),
  Endpoint.new("/counter", "GET", [
    Param.new("step", "", "query"),
  ]),
  Endpoint.new("/counter/{Start}", "GET", [
    Param.new("Start", "", "path"),
    Param.new("step", "", "query"),
  ]),
  Endpoint.new("/contact", "GET", [
    Param.new("ref", "", "query"),
  ]),
  Endpoint.new("/contact", "POST", [
    Param.new("Model", "", "form"),
  ]),
  Endpoint.new("/weather", "GET", [
    Param.new("City", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/csharp/razor/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "Razor components", tags: "functional" do
  it "names a component's OnInitialized override as the handler, in the .razor file or its code-behind" do
    counter = tester.app.endpoints.find! { |e| e.url == "/counter" && e.method == "GET" }
    counter.handler.try { |h| {h.name, h.path.to_s.ends_with?("Counter.razor"), h.line} }.should eq({"OnInitialized", true, 13})
    weather = tester.app.endpoints.find! { |e| e.url == "/weather" && e.method == "GET" }
    weather.handler.try { |h| {h.name, h.path.to_s.ends_with?("Weather.razor.cs"), h.line} }.should eq({"OnInitializedAsync", true, 6})
  end

  it "skips the pages of a .NET MAUI Blazor Hybrid project, which has no HTTP server" do
    tester.app.endpoints.any? { |e| e.url == "/native" }.should be_false
  end
end
