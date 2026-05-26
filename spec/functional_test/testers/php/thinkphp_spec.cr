require "../../func_spec.cr"

expected_endpoints = [
  # Explicit routes from route/app.php
  Endpoint.new("/hello/{name}", "GET", [
    Param.new("name", "", "path"),
  ]),
  Endpoint.new("/save", "POST"),
  Endpoint.new("/update", "PUT"),
  Endpoint.new("/update", "PATCH"),

  # Resource routes generated for "blog"
  Endpoint.new("/blog", "GET"),
  Endpoint.new("/blog/create", "GET"),
  Endpoint.new("/blog", "POST"),
  Endpoint.new("/blog/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}/edit", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/blog/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),

  # Group routes with "admin" prefix
  Endpoint.new("/admin/dashboard", "GET"),
  Endpoint.new("/admin/users", "POST"),

  # Implicit routes from app/controller/UserController.php
  Endpoint.new("/user/index", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/user", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/user/view", "GET", [
    Param.new("id", "", "query"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/user/view", "POST", [
    Param.new("id", "", "query"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/user/create", "GET", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/user/create", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),

  # Test: Nested controller subdirectories (slash & dot mappings)
  Endpoint.new("/admin/group/index", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/admin.group/index", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/admin/group", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/admin.group", "GET", [
    Param.new("id", "", "query"),
  ]),

  # Test: Multi-app route prefix auto-extraction (/shop prefix)
  Endpoint.new("/shop/orders", "GET"),

  # Test: Annotation/Attribute Routes inside controllers
  Endpoint.new("/home", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/profile/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/profile/{id}", "POST", [
    Param.new("id", "", "path"),
    Param.new("get_id", "", "query"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/user/advanced", "GET", [
    Param.new("verbose", "", "query"),
    Param.new("admin_token", "", "query"),
    Param.new("query_facade", "", "query"),
    Param.new("X-Facade-Header", "", "header"),
    Param.new("username_raw", "", "form"),
    Param.new("X-Correlation-Id", "", "header"),
    Param.new("email", "", "form"),
    Param.new("phone", "", "form"),
    Param.new("crmeb_page", "", "query"),
    Param.new("crmeb_limit", "", "query"),
    Param.new("crmeb_form_field", "", "form"),
  ]),
  Endpoint.new("/user/advanced", "POST", [
    Param.new("verbose", "", "query"),
    Param.new("admin_token", "", "query"),
    Param.new("query_facade", "", "query"),
    Param.new("X-Facade-Header", "", "header"),
    Param.new("username_raw", "", "form"),
    Param.new("X-Correlation-Id", "", "header"),
    Param.new("email", "", "form"),
    Param.new("phone", "", "form"),
    Param.new("crmeb_page", "", "query"),
    Param.new("crmeb_limit", "", "query"),
    Param.new("crmeb_form_field", "", "form"),
  ]),

  # Route::any endpoint expectations
  Endpoint.new("/any-route", "GET"),
  Endpoint.new("/any-route", "POST"),
  Endpoint.new("/any-route", "PUT"),
  Endpoint.new("/any-route", "PATCH"),
  Endpoint.new("/any-route", "DELETE"),
  Endpoint.new("/any-route", "OPTIONS"),
  Endpoint.new("/any-route", "HEAD"),

  # Route::rule with '*' endpoint expectations
  Endpoint.new("/rule-route", "GET"),
  Endpoint.new("/rule-route", "POST"),
  Endpoint.new("/rule-route", "PUT"),
  Endpoint.new("/rule-route", "PATCH"),
  Endpoint.new("/rule-route", "DELETE"),
  Endpoint.new("/rule-route", "OPTIONS"),
  Endpoint.new("/rule-route", "HEAD"),
]

FunctionalTester.new("fixtures/php/thinkphp/", {
  :techs     => 2,
  :endpoints => 43,
}, expected_endpoints).perform_tests
