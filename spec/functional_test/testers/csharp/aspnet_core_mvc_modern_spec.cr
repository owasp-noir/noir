require "../../func_spec.cr"

# Modern controller styles: C# 12 primary constructors, POCO controllers with
# no `: Controller` base, and expression-bodied actions delegating to MediatR.
articles_list = Endpoint.new("/articles", "GET", [
  Param.new("tag", "", "query"),
  Param.new("limit", "", "query"),
])
articles_list.push_callee(Callee.new("mediator.Send"))

article_get = Endpoint.new("/articles/{slug}", "GET", [
  Param.new("slug", "", "path"),
])

article_create = Endpoint.new("/articles", "POST", [
  Param.new("command", "", "json"),
])

users_create = Endpoint.new("/users", "POST", [
  Param.new("command", "", "json"),
])

users_login = Endpoint.new("/users/login", "POST", [
  Param.new("command", "", "json"),
])

# A single action carrying several [Http*] attributes emits one endpoint per
# verb (GET+HEAD file serving, GET+POST search), not only the last attribute.
file_download_get = Endpoint.new("/Files/{id}/Download", "GET", [Param.new("id", "", "path")])
file_download_head = Endpoint.new("/Files/{id}/Download", "HEAD", [Param.new("id", "", "path")])
file_search_get = Endpoint.new("/Files/Search", "GET", [Param.new("q", "", "query")])
file_search_post = Endpoint.new("/Files/Search", "POST", [Param.new("q", "", "query")])

# [AcceptVerbs] declares one action answering several verbs, at the
# conventional route or at an explicit `Route = "…"`.
banks_update_put = Endpoint.new("/banks", "PUT", [Param.new("accountNumber", "", "form")])
banks_update_patch = Endpoint.new("/banks", "PATCH", [Param.new("accountNumber", "", "form")])
banks_transfer_put = Endpoint.new("/banks/transfer", "PUT", [Param.new("amount", "", "form")])
banks_transfer_post = Endpoint.new("/banks/transfer", "POST", [Param.new("amount", "", "form")])

# QUERY (RFC 10008) routes through [AcceptVerbs] like any other verb string;
# the [Route("search")] base arrives on the line after [AcceptVerbs("QUERY")]
# and is still picked up.
# The `[FromBody] FilterDto` body is its members, camelCased as JSON.
banks_search_query = Endpoint.new("/banks/search", "QUERY", [Param.new("keyword", "", "json")])

# An unattributed parameter on a QUERY action binds from the body, same as
# it does on PUT/POST/PATCH, not from the URL query string.
banks_search_implicit = Endpoint.new("/banks/search/implicit", "QUERY", [Param.new("keyword", "", "form")])

# `[FromRoute(Name = "branchId")] string internalBranchKey` binds the route
# value, so the parameter is `branchId`; `{page=5}` carries a template default
# that is not part of the URL.
banks_branch = Endpoint.new("/banks/branch/{branchId}", "GET", [Param.new("branchId", "", "path")])
banks_page = Endpoint.new("/banks/page/{page}", "GET", [Param.new("page", "", "path")])
banks_audit = Endpoint.new("/banks/audit", "GET", [Param.new("X-Tenant", "", "header")])
banks_open = Endpoint.new("/banks/open", "POST", [Param.new("Owner", "", "form"), Param.new("Kind", "", "form")])

# Body DTOs carry the members they inherit, resolved through namespaces and
# `using`s; getter-only and privately-set members are never request input.
members_update = Endpoint.new("/members/{id}", "PUT", [
  Param.new("id", "", "path"),
  Param.new("email", "", "json"),
  Param.new("externalId", "", "json"),
  Param.new("role", "", "json"),
  Param.new("home", "", "json"),
  Param.new("otp", "", "json"),
  Param.new("tags", "", "json"),
])
members_batch = Endpoint.new("/members/batch", "POST", [Param.new("type", "", "json"), Param.new("ts", "", "json")])
members_profile = Endpoint.new("/members/{id}/profile", "GET", [Param.new("id", "", "path"), Param.new("tags", "", "query")])
members_trial = Endpoint.new("/members/trial", "POST", [
  Param.new("trialLength", "", "json"),
  Param.new("name", "", "json"),
  Param.new("email", "", "json"),
])
# A JSON array body is its element type's members.
members_events = Endpoint.new("/members/events", "POST", [Param.new("type", "", "json"), Param.new("ts", "", "json")])
members_cycle = Endpoint.new("/members/cycle", "POST", [Param.new("left", "", "json"), Param.new("right", "", "json")])

# Property and type shapes: block-bodied accessors, an initialized
# getter-only collection, redeclared base members, [JsonConstructor]
# parameters, a same-file namespace pick, a nested-type base, and binders.
shapes_accessors = Endpoint.new("/shapes/accessors", "POST", %w[name email tags].map { |n| Param.new(n, "", "json") })
shapes_override = Endpoint.new("/shapes/override", "POST", %w[shadow_x keep].map { |n| Param.new(n, "", "json") })
shapes_ctor = Endpoint.new("/shapes/ctor", "POST", %w[count fooName].map { |n| Param.new(n, "", "json") })
shapes_versioned = Endpoint.new("/shapes/versioned", "POST", %w[own fromV2].map { |n| Param.new(n, "", "json") })
shapes_nested_base = Endpoint.new("/shapes/nested-base", "POST", %w[shallow deep].map { |n| Param.new(n, "", "json") })
shapes_grid = Endpoint.new("/shapes/grid", "POST", [Param.new("grid", "", "json")])
shapes_binders = Endpoint.new("/shapes/binders", "GET", %w[filter sort ids].map { |n| Param.new(n, "", "query") })

expected_endpoints = [
  articles_list,
  article_get,
  article_create,
  users_create,
  users_login,
  file_download_get,
  file_download_head,
  file_search_get,
  file_search_post,
  banks_update_put,
  banks_update_patch,
  banks_transfer_put,
  banks_transfer_post,
  banks_search_query,
  banks_search_implicit,
  banks_branch,
  banks_page,
  banks_audit,
  banks_open,
  members_update,
  members_trial,
  members_events,
  members_cycle,
  members_profile,
  members_batch,
  shapes_accessors,
  shapes_override,
  shapes_ctor,
  shapes_versioned,
  shapes_nested_base,
  shapes_grid,
  shapes_binders,
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_modern/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "ASP.NET Core MVC modern controller edge cases", tags: "functional" do
  it "resolves actions on a primary-constructor controller" do
    list = tester.app.endpoints.find { |e| e.url == "/articles" && e.method == "GET" }
    list.should_not be_nil
  end

  it "resolves actions on a POCO controller with no base class" do
    login = tester.app.endpoints.find { |e| e.url == "/users/login" && e.method == "POST" }
    login.should_not be_nil
  end

  it "drops the ambient CancellationToken from expression-bodied actions" do
    list = tester.app.endpoints.find { |e| e.url == "/articles" && e.method == "GET" }
    list.should_not be_nil
    list.as(Endpoint).params.any? { |p| p.name == "cancellationToken" }.should be_false
  end

  it "emits one endpoint per verb listed in [AcceptVerbs]" do
    tester.app.endpoints.count { |e| e.url == "/banks" }.should eq 2
    tester.app.endpoints.count { |e| e.url == "/banks/transfer" }.should eq 2
  end

  it "recognizes QUERY (RFC 10008) in [AcceptVerbs] with its [Route] base and body param" do
    search = tester.app.endpoints.find! { |e| e.url == "/banks/search" && e.method == "QUERY" }
    search.params.map(&.name).should eq(["keyword"])
    search.params.first.param_type.should eq "json"
  end

  it "binds an unattributed QUERY parameter from the body, not the query string" do
    implicit = tester.app.endpoints.find! { |e| e.url == "/banks/search/implicit" && e.method == "QUERY" }
    implicit.params.map(&.name).should eq(["keyword"])
    implicit.params.first.param_type.should eq "form"
  end

  it "uses the explicit [From*(Name = ...)] binding name, not the C# identifier" do
    branch = tester.app.endpoints.find! { |e| e.url == "/banks/branch/{branchId}" }
    branch.params.map(&.name).sort!.should eq(["branchId"])
  end

  it "strips a route-template default value from the URL and the param name" do
    tester.app.endpoints.any?(&.url.includes?("{page=5}")).should be_false
    page = tester.app.endpoints.find! { |e| e.url == "/banks/page/{page}" }
    page.params.map(&.name).should eq(["page"])
  end

  it "names the action as the handler, at its signature rather than its attribute" do
    audit = tester.app.endpoints.find! { |e| e.url == "/banks/audit" }
    audit.handler.try { |h| {h.name, h.line} }.should eq({"BanksController.Audit", 38})
  end

  it "reads inherited body members from the base the namespace resolves to" do
    update = tester.app.endpoints.find! { |e| e.url == "/members/{id}" }
    update.params.map(&.name).sort!.should eq(["email", "externalId", "home", "id", "otp", "role", "tags"])
    trial = tester.app.endpoints.find! { |e| e.url == "/members/trial" }
    trial.params.map(&.name).sort!.should eq(["email", "name", "trialLength"])
  end

  it "expands a JSON collection body to its element's members" do
    events = tester.app.endpoints.find! { |e| e.url == "/members/events" }
    events.params.map(&.name).should eq(["type", "ts"])
  end

  it "drops parameters the request never supplies ([BindNever], server-side binders)" do
    profile = tester.app.endpoints.find! { |e| e.url == "/members/{id}/profile" }
    profile.params.map(&.name).sort!.should eq(["id", "tags"])
  end

  it "reads exactly the members each body shape exposes" do
    [shapes_accessors, shapes_override, shapes_ctor, shapes_versioned, shapes_nested_base, shapes_grid, shapes_binders].each do |expected|
      found = tester.app.endpoints.find! { |e| e.url == expected.url && e.method == expected.method }
      found.params.map(&.name).sort!.should eq(expected.params.map(&.name).sort!)
    end
  end

  it "records callees from an expression-bodied action body" do
    list = tester.app.endpoints.find { |e| e.url == "/articles" && e.method == "GET" }
    list.should_not be_nil
    list.as(Endpoint).callees.map(&.name).any? { |n| n == "mediator.Send" }.should be_true
  end
end
