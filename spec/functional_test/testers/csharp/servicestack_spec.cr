require "../../func_spec.cr"

expected_endpoints = [
  # Attribute-routed DTOs (ServiceModel/Hello.cs): two [Route] attributes on
  # one class, each answering GET independently.
  Endpoint.new("/hello", "GET", [
    Param.new("Name", "", "query"),
  ]),
  Endpoint.new("/hello/{Name}", "GET", [
    Param.new("Name", "", "path"),
  ]),

  # Attribute-routed DTO (ServiceModel/Movies.cs) with two independent
  # [Route] attributes: /movies only answers the write verbs its own
  # attribute names, /movies/{Id} (a *different* attribute, no verb list)
  # answers every verb. The two must not cross-multiply.
  Endpoint.new("/movies", "POST", [
    Param.new("Id", "", "json"),
    Param.new("Title", "", "json"),
  ]),
  Endpoint.new("/movies", "PUT", [
    Param.new("Id", "", "json"),
    Param.new("Title", "", "json"),
  ]),
  Endpoint.new("/movies", "PATCH", [
    Param.new("Id", "", "json"),
    Param.new("Title", "", "json"),
  ]),
  Endpoint.new("/movies", "DELETE", [
    Param.new("Id", "", "query"),
    Param.new("Title", "", "query"),
  ]),
  Endpoint.new("/movies/{Id}", "ANY", [
    Param.new("Id", "", "path"),
    Param.new("Title", "", "json"),
  ]),

  # Fluent `Routes.Add<T>(...)` registrations (AppHost.cs). `Hello`'s
  # properties are declared in a different file, so resolving them exercises
  # the cross-file type index.
  Endpoint.new("/hello2", "ANY", [
    Param.new("Name", "", "json"),
  ]),
  Endpoint.new("/hello2/{Name}", "ANY", [
    Param.new("Name", "", "path"),
  ]),
  Endpoint.new("/contacts", "GET", [
    Param.new("ContactId", "", "query"),
  ]),

  # A plain ASP.NET Core MVC controller that happens to live in a project
  # that also references ServiceStack. Owned by cs_aspnet_core_mvc — see the
  # "project scoping" describe block below.
  Endpoint.new("/api/Unrelated", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/servicestack/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ServiceStack analyzer edge cases" do
  it "does not surface routes from /test/ fixtures" do
    tester.app.endpoints.any?(&.url.includes?("test-only")).should be_false
  end

  it "marks attribute-routed DTOs with the cs_servicestack technology" do
    hello = tester.app.endpoints.find { |e| e.url == "/hello" && e.method == "GET" }
    hello.should_not be_nil
    hello.as(Endpoint).details.technology.should eq "cs_servicestack"
  end

  it "marks fluent Routes.Add<T> registrations with the cs_servicestack technology" do
    contacts = tester.app.endpoints.find { |e| e.url == "/contacts" && e.method == "GET" }
    contacts.should_not be_nil
    contacts.as(Endpoint).details.technology.should eq "cs_servicestack"
  end

  it "does not steal ASP.NET Core MVC's [Route]-decorated controller" do
    controller_endpoint = tester.app.endpoints.find { |e| e.url == "/api/Unrelated" }
    controller_endpoint.should_not be_nil
    controller_endpoint.as(Endpoint).details.technology.should eq "cs_aspnet_core_mvc"

    # No duplicate emitted by the ServiceStack analyzer for the same route.
    tester.app.endpoints.count { |e| e.url == "/api/Unrelated" }.should eq 1
  end

  it "does not cross-multiply independent [Route] attributes' verb lists" do
    # /movies only ever answers the verbs its own attribute names.
    tester.app.endpoints.any? { |e| e.url == "/movies" && e.method == "GET" }.should be_false
    tester.app.endpoints.any? { |e| e.url == "/movies" && e.method == "ANY" }.should be_false
  end
end
