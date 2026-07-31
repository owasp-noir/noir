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

# `[FromRoute(Name = "branchId")] string internalBranchKey` binds the route
# value, so the parameter is `branchId`; `{page=5}` carries a template default
# that is not part of the URL.
banks_branch = Endpoint.new("/banks/branch/{branchId}", "GET", [Param.new("branchId", "", "path")])
banks_page = Endpoint.new("/banks/page/{page}", "GET", [Param.new("page", "", "path")])
banks_audit = Endpoint.new("/banks/audit", "GET", [Param.new("X-Tenant", "", "header")])

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
  banks_branch,
  banks_page,
  banks_audit,
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_modern/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})

tester.perform_tests

describe "ASP.NET Core MVC modern controller edge cases" do
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

  it "uses the explicit [From*(Name = ...)] binding name, not the C# identifier" do
    branch = tester.app.endpoints.find! { |e| e.url == "/banks/branch/{branchId}" }
    branch.params.map(&.name).sort!.should eq(["branchId"])
  end

  it "strips a route-template default value from the URL and the param name" do
    tester.app.endpoints.any?(&.url.includes?("{page=5}")).should be_false
    page = tester.app.endpoints.find! { |e| e.url == "/banks/page/{page}" }
    page.params.map(&.name).should eq(["page"])
  end

  it "records callees from an expression-bodied action body" do
    list = tester.app.endpoints.find { |e| e.url == "/articles" && e.method == "GET" }
    list.should_not be_nil
    list.as(Endpoint).callees.map(&.name).any? { |n| n == "mediator.Send" }.should be_true
  end
end
