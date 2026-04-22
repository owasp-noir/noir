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
    Param.new("session", "", "cookie"),
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

  # ---- App Router: /api/products (named GET + POST exports) ----
  Endpoint.new("/api/products", "GET", [
    Param.new("q", "", "query"),
  ]),
  Endpoint.new("/api/products", "POST"),

  # ---- App Router: /api/products/{id} (GET + PUT + DELETE) ----
  Endpoint.new("/api/products/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("x-token", "", "header"),
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
