require "../../func_spec.cr"

# Declarations the C# analyzers and the ASP.NET auth tagger read off
# `Noir::CSharpDeclParser`: attribute lists holding several attributes,
# attributes and signatures split over lines, `#if` inside an attribute
# stack, strings and comments that spell attributes or classes, parameter
# defaults with commas, nested classes.
describe "C# declaration shapes", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/csharp/decl_shapes/#{fixture}/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end
  find = ->(endpoints : Array(Endpoint), method : String, url : String) do
    endpoints.find { |e| e.method == method && e.url == url }
  end
  guarded = ->(endpoints : Array(Endpoint), method : String, url : String) do
    ep = endpoints.find! { |e| e.method == method && e.url == url }
    !(ep.ai_context.try(&.guards.empty?) || ep.ai_context.nil?)
  end
  params = ->(endpoints : Array(Endpoint), method : String, url : String) do
    endpoints.find! { |e| e.method == method && e.url == url }.params.map { |p| "#{p.param_type}:#{p.name}" }.sort!
  end

  it "reads every action attribute, however the list and signature are laid out" do
    endpoints = scan.call("mvc")
    {
      {"POST", "/api/orders/create"}, {"GET", "/api/orders/feed"}, {"HEAD", "/api/orders/feed"},
      {"GET", "/api/orders/named/{id}"}, {"GET", "/api/orders/by/{id}"}, {"GET", "/api/orders/split/{id}"},
      {"GET", "/api/orders/tuple"}, {"PATCH", "/api/orders/patch/{id}"}, {"GET", "/api/orders/cond"},
      {"GET", "/api/v3/books/{id}"}, {"GET", "/api/items/{id}"}, {"GET", "/api/split/one"},
    }.each { |(method, url)| find.call(endpoints, method, url).should_not be_nil }
    # Strings, raw strings and comments that spell an action are not one.
    find.call(endpoints, "DELETE", "/api/orders").should be_nil
    find.call(endpoints, "POST", "/api/orders/raw").should be_nil
    find.call(endpoints, "PUT", "/api/orders/ghost").should be_nil
    find.call(endpoints, "GET", "/api/orders").should be_nil
    params.call(endpoints, "GET", "/api/orders/search").should eq ["header:X-Trace", "query:page", "query:q"]
    params.call(endpoints, "GET", "/api/orders/split/{id}").should eq ["path:id"]
  end

  it "reads [Authorize] / [AllowAnonymous] off the declarations" do
    endpoints = scan.call("mvc")
    guarded.call(endpoints, "POST", "/api/orders/create").should be_true
    guarded.call(endpoints, "GET", "/api/secure/a").should be_true
    guarded.call(endpoints, "GET", "/api/secure/open").should be_false
    guarded.call(endpoints, "GET", "/api/secure/b").should be_true
    guarded.call(endpoints, "GET", "/api/secure/c").should be_true
    guarded.call(endpoints, "GET", "/api/cond/x").should be_true
    guarded.call(endpoints, "GET", "/api/plain/admin").should be_true
    guarded.call(endpoints, "GET", "/api/plain/free").should be_false
    guarded.call(endpoints, "GET", "/api/plain/roles").should be_true
    guarded.call(endpoints, "GET", "/api/plain/after-roles").should be_false
    guarded.call(endpoints, "GET", "/api/inline/y").should be_true
    guarded.call(endpoints, "GET", "/api/outer/after-nested").should be_true
    guarded.call(endpoints, "GET", "/api/items/{id}").should be_true
    guarded.call(endpoints, "GET", "/api/split/one").should be_false
  end

  it "reads minimal API auth on masked statements only" do
    endpoints = scan.call("minimal")
    guarded.call(endpoints, "POST", "/m4").should be_true
    guarded.call(endpoints, "GET", "/m1").should be_false
    # The one-line `[Authorize]` method around the route is not its handler.
    endpoints.find! { |e| e.url == "/m6" }.tags.map(&.name).should_not contain("auth")
    find.call(endpoints, "POST", "/ghost").should be_nil
  end

  it "reads Wolverine, classic MVC, Carter and FastEndpoints declarations" do
    wolverine = scan.call("wolv")
    find.call(wolverine, "DELETE", "/orders/{id}").should_not be_nil
    find.call(wolverine, "POST", "/phantom").should be_nil
    guarded.call(wolverine, "POST", "/orders").should be_true

    classic = scan.call("classic")
    params.call(classic, "POST", "/account/login").should eq ["form:returnUrl", "form:user"]
    find.call(classic, "GET", "/account/orders/{id}").should_not be_nil
    guarded.call(classic, "GET", "/account/register").should be_false
    guarded.call(classic, "GET", "/account/profile").should be_true

    carter = scan.call("carter")
    find.call(carter, "GET", "/books").should_not be_nil
    find.call(carter, "GET", "/authors/{id}").should_not be_nil

    fast = scan.call("fe")
    params.call(fast, "POST", "/users").should eq ["header:X-Tenant", "json:Name", "json:a]b", "query:Page"]
  end
end
