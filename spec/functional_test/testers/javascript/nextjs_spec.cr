require "../../func_spec.cr"

expected_endpoints = [
  # ---- Pages Router: /api/users (default export, all methods) ----
  Endpoint.new("/api/users", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("search", "", "query"),
    Param.new("username", "", "body"),
    Param.new("email", "", "body"),
  ]),
  Endpoint.new("/api/users", "POST", [
    Param.new("page", "", "query"),
    Param.new("username", "", "body"),
    Param.new("email", "", "body"),
  ]),
  Endpoint.new("/api/users", "PUT"),
  Endpoint.new("/api/users", "DELETE"),
  Endpoint.new("/api/users", "PATCH"),

  # ---- Pages Router: /api/users/{id} ([id].ts) ----
  Endpoint.new("/api/users/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-token", "", "header"),
    Param.new("SIGNATURE_HEADER", "", "header"),
    Param.new("session", "", "cookie"),
    Param.new("SESSION_COOKIE", "", "cookie"),
  ]),
  Endpoint.new("/api/users/{id}", "POST", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/users/{id}", "PUT"),
  Endpoint.new("/api/users/{id}", "DELETE"),
  Endpoint.new("/api/users/{id}", "PATCH"),

  # ---- Pages Router: /api/posts/{slug} ([...slug] catch-all) ----
  Endpoint.new("/api/posts/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/api/posts/{slug}", "POST"),
  Endpoint.new("/api/posts/{slug}", "PUT"),
  Endpoint.new("/api/posts/{slug}", "DELETE"),
  Endpoint.new("/api/posts/{slug}", "PATCH"),

  # ---- Pages Router: /api/auth/login (POST-only inferred from req.method check) ----
  Endpoint.new("/api/auth/login", "POST", [
    Param.new("username", "", "body"),
    Param.new("password", "", "body"),
  ]),

  # ---- Pages Router: switch(req.method) inference ----
  Endpoint.new("/api/switch", "GET", [
    Param.new("cursor", "", "query"),
    Param.new("id", "", "body"),
  ]),
  Endpoint.new("/api/switch", "DELETE", [
    Param.new("cursor", "", "query"),
    Param.new("id", "", "body"),
  ]),
  # ---- Pages Router: unrelated HTTP-like switch cases should not suppress fallback methods ----
  Endpoint.new("/api/unrelated-switch", "GET", [
    Param.new("type", "", "query"),
  ]),
  Endpoint.new("/api/unrelated-switch", "POST", [
    Param.new("type", "", "query"),
  ]),
  Endpoint.new("/api/unrelated-switch", "PUT", [
    Param.new("type", "", "query"),
  ]),
  Endpoint.new("/api/unrelated-switch", "DELETE", [
    Param.new("type", "", "query"),
  ]),
  Endpoint.new("/api/unrelated-switch", "PATCH", [
    Param.new("type", "", "query"),
  ]),

  # ---- App Router: /api/products (named GET + POST exports) ----
  Endpoint.new("/api/products", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/products", "POST"),

  # ---- App Router: /api/products/{id} (GET + PUT + DELETE) ----
  Endpoint.new("/api/products/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-token", "", "header"),
    Param.new("WEBHOOK_SECRET", "", "header"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/api/products/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/api/products/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # ---- App Router: /api/search (GET, multiple searchParams) ----
  Endpoint.new("/api/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),

  # ---- App Router: /settings (route group (dashboard) stripped) ----
  Endpoint.new("/settings", "GET", [
    Param.new("theme", "", "query"),
  ]),

  # ---- App Router: /api/upload (formData) ----
  Endpoint.new("/api/upload", "POST", [
    Param.new("file", "", "form"),
    Param.new("description", "", "form"),
  ]),
  # ---- App Router: aliased form/cookie helpers and headers() ----
  Endpoint.new("/api/profile", "POST", [
    Param.new("avatar", "", "form"),
    Param.new("session", "", "cookie"),
    Param.new("x-forwarded-for", "", "header"),
  ]),
  # ---- App Router: commented method exports do not emit routes ----
  Endpoint.new("/api/commented", "POST"),

  # ---- App Router: method-local params in the same route.ts ----
  Endpoint.new("/api/scoped", "GET", [
    Param.new("q", "", "query"),
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/api/scoped", "POST", [
    Param.new("username", "", "json"),
  ]),

  # ---- Server Actions (app/actions/user.ts with "use server") ----
  Endpoint.new("/createUser", "POST", [
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
  ]),
  Endpoint.new("/deleteUser", "POST", [
    Param.new("id", "", "body"),
  ]),
]

FunctionalTester.new("fixtures/javascript/nextjs/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Next.js variable header keys" do
  it "surfaces identifier names for req.headers[CONST] and request.headers.get(CONST)" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    pages_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/users/{id}" }
    pages_get.params.any? { |p| p.name == "SIGNATURE_HEADER" && p.param_type == "header" }.should be_true
    pages_get.params.any? { |p| p.name == "SESSION_COOKIE" && p.param_type == "cookie" }.should be_true

    app_get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/products/{id}" }
    app_get.params.any? { |p| p.name == "WEBHOOK_SECRET" && p.param_type == "header" }.should be_true
  end
end

describe "Next.js comment filtering" do
  it "does not emit endpoints for commented-out exports (// and /* */)" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.none? { |ep| ep.url == "/api/commented" && ep.method == "GET" }.should be_true
    app.endpoints.none? { |ep| ep.url == "/api/commented" && ep.method == "DELETE" }.should be_true
    app.endpoints.any? { |ep| ep.url == "/api/commented" && ep.method == "POST" }.should be_true
  end
end

describe "Next.js App Router method-local params" do
  it "does not leak GET query params onto POST handlers in the same route file" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    post = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/api/scoped" }
    post.params.any? { |param| param.name == "q" && param.param_type == "query" }.should be_false
    post.params.any? { |param| param.name == "page" && param.param_type == "query" }.should be_false
    post.params.any? { |param| param.name == "username" && param.param_type == "json" }.should be_true
  end
end

describe "Next.js source attribution" do
  it "uses handler and server-action lines instead of the file start" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/nextjs/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    pages = app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/api/users" }
    pages.details.code_paths.first.line.should eq(3)

    app_get = app.endpoints.find! { |endpoint| endpoint.method == "GET" && endpoint.url == "/api/products/{id}" }
    app_get.details.code_paths.first.line.should eq(8)

    app_delete = app.endpoints.find! { |endpoint| endpoint.method == "DELETE" && endpoint.url == "/api/products/{id}" }
    app_delete.details.code_paths.first.line.should eq(20)

    create_action = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/createUser" }
    create_action.details.code_paths.first.line.should eq(3)

    delete_action = app.endpoints.find! { |endpoint| endpoint.method == "POST" && endpoint.url == "/deleteUser" }
    delete_action.details.code_paths.first.line.should eq(9)
  end
end
