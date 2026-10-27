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

    # `->middleware($middleware)` names the literal list the variable holds,
    # at file scope or captured by `use ($middleware)`; a closure that did
    # not capture it sees no variable.
    auth = ["Laravel auth:sanctum,api middleware"]
    guards.call(find.call("GET", "/vars/direct")).should eq(auth)
    guards.call(find.call("GET", "/vars/captured")).should eq(auth)
    guards.call(find.call("GET", "/vars/grouped")).should eq(auth)
    guards.call(find.call("GET", "/vars/uncaptured")).should be_empty

    # A group behind `domain(config(...))` is still a group, and
    # `prefix(config('file.key'))` reads config/file.php's default.
    find.call("GET", "/i/portfolio/cfg")
    find.call("GET", "/deep/cfg")
    find.call("GET", "/fallback/cfg")
    endpoints.none?(&.url.==("/cfg")).should be_true

    # Constructor `$this->middleware(...)` (own or inherited), limited by
    # `->only` / `->except`, judged like route middleware: `staff` redirects
    # a guest away, `guest` redirects a signed-in user. A closure middleware
    # is not a name; one under a config check carries the setting note.
    staff = ["Laravel 'staff' middleware (Staff)"]
    setting = "an environment or config check decides; a setting can make it public"
    guards.call(find.call("GET", "/acct/open")).should eq(["Laravel auth middleware (controller constructor: #{setting})"])
    guards.call(find.call("POST", "/acct/close")).should eq(staff)
    guards.call(find.call("POST", "/staff/close")).should eq(staff)
    find.call("GET", "/acct/open").params.map(&.name).should eq(["_pe"])

    # An action a used trait defines is served there; its loop over a
    # literal field list and its paginator's page name are read.
    profile = find.call("POST", "/acct/profile")
    guards.call(profile).should eq(staff)
    profile.handler.should_not be_nil
    profile.handler.not_nil!.path.to_s.should end_with("Concerns/ManagesProfile.php")
    profile.params.map(&.name).sort!.should eq(["bio", "p", "website"])

    # A handler that refuses a guest first is guarded by it; one that
    # returns before, nests the check, or checks a property is not.
    guards.call(find.call("GET", "/check/mine")).should eq(["Laravel handler check (abort_unless($request->user(), 404))"])
    find.call("GET", "/check/mine").params.map(&.name).should eq(["page"])
    guards.call(find.call("GET", "/check/own")).should eq(["Laravel handler check (if (! $user) refuses)"])
    guards.call(find.call("GET", "/check/late")).should be_empty
    guards.call(find.call("GET", "/check/after")).should be_empty
    guards.call(find.call("GET", "/check/validated")).should eq(["Laravel handler check (if (! $request->user()) refuses)"])
    guards.call(find.call("GET", "/check/role")).should be_empty
    # The `if (!user)` block must refuse before anything in it could answer.
    guards.call(find.call("GET", "/check/branch")).should be_empty
    guards.call(find.call("GET", "/check/guarded")).should be_empty

    # `middleware('auth', ['except' => [...]])` options limit the names of
    # the first argument; an unreadable `->except($this->public)` limit is
    # only a conditional guard; a brace-less `if (config(...))` body is
    # conditional; a child constructor inherits the parent's calls only
    # through `parent::__construct()`.
    guards.call(find.call("GET", "/ctor/index")).should eq(["Laravel 'staff' middleware (Staff) (controller constructor: its only/except list is not readable, so it may not apply to this action; a condition decides whether it applies)"])
    guards.call(find.call("POST", "/ctor/store")).should eq(["Laravel auth middleware"])
    guards.call(find.call("POST", "/ctor/parent")).should eq(["Laravel auth middleware"])
    guards.call(find.call("POST", "/ctor/override")).should be_empty
    guards.call(find.call("GET", "/ctor/braceless")).should eq(["Laravel auth middleware (controller constructor: #{setting})"])

    # `insteadof` picks the trait an action comes from; `as` aliases one.
    find.call("GET", "/feed").handler.not_nil!.path.to_s.should end_with("Concerns/OpenIndex.php")
    guards.call(find.call("GET", "/feed")).should be_empty
    find.call("GET", "/feed/locked").handler.not_nil!.path.to_s.should end_with("Concerns/LocksIndex.php")

    # A redirect in the `else` of `if (!Auth::check())` sends signed-in
    # users away, not guests.
    guards.call(find.call("GET", "/mw/guestonly")).should be_empty
    # The config file's own `return [`, not one inside a closure.
    find.call("GET", "/later/cfg")
    # A function parameter shadows the file-scope `$middleware`.
    guards.call(find.call("GET", "/vars/shadowed")).should be_empty

    inner = find.call("GET", "/check/inner/{id}")
    guards.call(inner).should be_empty
    inner.params.map(&.name).should eq(["id"])
  end
end
