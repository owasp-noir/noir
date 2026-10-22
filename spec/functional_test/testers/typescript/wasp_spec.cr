require "../../func_spec.cr"

# Wasp DSL (`main.wasp`). Routes follow waspc's server generator:
# operations are `POST /operations/<kebab-name>`, CRUDs
# `POST /crud/<name>/<op>`, `apiNamespace` adds middleware only.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/tasks/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/foo/bar", "GET", [Param.new("search", "", "query")]),
  Endpoint.new("/profile/:userId", "PUT", [
    Param.new("userId", "", "path"),
    Param.new("displayName", "", "json"),
    Param.new("bio", "", "json"),
    Param.new("x-profile-token", "", "header"),
  ]),
  Endpoint.new("/operations/create-task", "POST", [
    Param.new("description", "", "json"),
    Param.new("dueDate", "", "json"),
  ]),
  Endpoint.new("/operations/get-tasks", "POST", [
    Param.new("status", "", "json"),
    Param.new("limit", "", "json"),
  ]),
  Endpoint.new("/operations/get-httpstatus", "POST"),
  Endpoint.new("/crud/tasks/get-all", "POST"),
  Endpoint.new("/crud/tasks/get", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/crud/tasks/create", "POST", [
    Param.new("title", "", "json"),
    Param.new("priority", "", "json"),
  ]),
  Endpoint.new("/crud/tasks/delete", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/auth/me", "GET"),
  Endpoint.new("/auth/logout", "POST"),
  Endpoint.new("/auth/username/login", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/username/signup", "POST", [Param.new("username", "", "json"), Param.new("password", "", "json")]),
  Endpoint.new("/auth/google/login", "GET"),
  Endpoint.new("/auth/google/callback", "GET", [Param.new("code", "", "query"), Param.new("state", "", "query")]),
  Endpoint.new("/auth/exchange-code", "POST", [Param.new("code", "", "json")]),
] of Endpoint

# `httpRoute: (ALL, "/webhook")` is Express `router.all`.
%w[GET POST PUT DELETE PATCH HEAD OPTIONS].each do |method|
  expected_endpoints << Endpoint.new("/webhook", method, [
    Param.new("event", "", "json"),
    Param.new("X-Signature", "", "header"),
  ])
end

FunctionalTester.new("fixtures/typescript/wasp/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Wasp endpoint tags", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports auth: false, CRUD guards and client-only page auth" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/wasp/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    find = ->(method : String, url : String) { app.endpoints.find! { |ep| ep.method == method && ep.url == url } }
    tags = ->(method : String, url : String) { find.call(method, url).tags.map { |tag| {tag.name, tag.description} } }

    tags.call("GET", "/foo/bar").should contain({"wasp-auth", "auth: false; no session is resolved"})
    tags.call("PUT", "/profile/:userId").map(&.[0]).should_not contain("auth")
    tags.call("POST", "/crud/tasks/get").should contain({"auth", "Protected by Wasp CRUD authentication"})
    tags.call("POST", "/crud/tasks/get-all").map(&.[0]).should_not contain("auth")
    # An overridden CRUD operation runs user code, which owns the check.
    tags.call("POST", "/crud/tasks/create").map(&.[0]).should_not contain("auth")
    tags.call("POST", "/operations/create-task").should contain({"wasp-operation", "action createTask"})
    tags.call("GET", "/").map(&.[0]).should contain("wasp-auth-required")
    # The handler file is the second code path.
    find.call("GET", "/foo/bar").details.code_paths.map { |code_path| File.basename(code_path.path) }.should eq ["main.wasp", "apis.ts"]
  end
end
