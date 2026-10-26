require "../../func_spec.cr"

# What an agent tracing a Laravel route needs from it:
#   * handler: the controller method's definition line, or a closure's start;
#   * auth: `routes/api.php` is loaded under the `api` group (RouteServiceProvider),
#     whose Kernel members include a middleware whose `handle()` throws
#     `AuthenticationException` (via a helper); the `web` group's only member
#     aborts 404, which is not a refusal; `withoutMiddleware` opts a route out;
#   * params: rules read from `$this->rules['update']`, a helper's local `$rules`
#     (array_merge + `$rules['x'] =`), `confirmed` -> `x_confirmation`, `filled()`;
#   * `->where('path', '.*$')` / `->whereNumber('id')` constrain the placeholder.
describe "Laravel handler / middleware-group auth / rules params", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/laravel_trust/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves what serves each route and who may call it" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
    find = ->(method : String, url : String) { endpoints.find! { |ep| ep.method == method && ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }

    update = find.call("PUT", "/api/items/{id}")
    handler = update.handler.should_not be_nil
    handler.name.should eq("ItemController@update")
    handler.path.to_s.should end_with("app/Http/Controllers/ItemController.php")
    handler.line.should eq(22)
    guards.call(update).should eq(["Laravel 'api' middleware group (TokenGate)"])
    update.params.map(&.name).sort!.should eq(["id", "tags", "title"])

    ping = find.call("GET", "/api/ping")
    guards.call(ping).should be_empty
    ping_handler = ping.handler.should_not be_nil
    ping_handler.name.should eq("closure")
    ping_handler.line.should eq(8)

    login = find.call("POST", "/login")
    guards.call(login).should be_empty
    login.params.map(&.name).sort!.should eq(["email", "otp", "password", "password_confirmation", "remember"])

    find.call("GET", "/files/{path:.*}").params.map(&.name).should eq(["path"])
    find.call("GET", "/items/{id:[0-9]+}").params.map(&.name).should eq(["id"])

    # `foreach` over a literal map: one route per entry, the key in the path
    # and the value as the action; a group's `TokenGate::class` is judged by
    # its definition. `show` reads `folder_name` from its FormRequest's trait
    # helper and `cursor` through `Pager::resolve($request)`.
    ping_rest = find.call("POST", "/rest/ping{format?}")
    ping_rest.handler.try(&.name).should eq("PingController@__invoke")
    guards.call(ping_rest).should eq(["Laravel TokenGate middleware"])
    show = find.call("GET", "/rest/show{format?}")
    show.handler.try(&.name).should eq("ItemController@show")
    show.details.code_paths.first.line.should eq(18)
    # Not `decoy` (`Arr` is Illuminate's, not app/Support/Arr.php), not
    # `tenant` (the request is not the helper's first parameter), not
    # `lookup_col` (an `array_merge` inside a rule's closure).
    show.params.map(&.name).sort!.should eq(["cursor", "folder_name", "format", "q", "slug"])

    # Not provably constant, a loop variable the body rewrites, or past the
    # expansion budget: the as-written route.
    find.call("GET", "/w/{name}")
    find.call("GET", "/s/{s}")
    find.call("GET", "/b/{kind}")
    find.call("GET", "/g/{x}/{y}")
    # Nested loops expand as a whole, never half.
    endpoints.map(&.url).select(&.starts_with?("/n/")).sort!.should eq(["/n/v1/teams", "/n/v1/users", "/n/v2/teams", "/n/v2/users"])
    # A loop inside a handler body registers at request time.
    endpoints.none?(&.url.starts_with?("/inner")).should be_true

    # Middleware classes judged by their definition: a refusal only in the
    # `local` environment, or on a CORS origin, is not an auth guard; one
    # under an environment check that also needs a user is, with a note.
    guards.call(find.call("GET", "/mw/token")).should eq(["Laravel TokenGate middleware"])
    guards.call(find.call("GET", "/mw/local")).should be_empty
    guards.call(find.call("GET", "/mw/cors")).should be_empty
    guards.call(find.call("GET", "/mw/prod")).should eq(["Laravel ProdGate middleware (an environment or config check decides; a setting can make it public)"])
  end
end
