require "../../func_spec.cr"

expected_endpoints = [
  # From config/web.php urlManager rules
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/posts/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/{id}", "PUT", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/{id}", "DELETE", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/articles/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/health", "GET"),
  # A comma-separated verb list declares one route per verb.
  Endpoint.new("/tags", "GET"),
  Endpoint.new("/tags", "HEAD"),
  # yii\rest\UrlRule expands to the pluralized controller's REST routes;
  # its own `'class' => …` options are not routes.
  Endpoint.new("/comments", "GET"),
  Endpoint.new("/comments", "HEAD"),
  Endpoint.new("/comments", "POST"),
  Endpoint.new("/comments", "OPTIONS"),
  Endpoint.new("/comments/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/comments/{id}", "HEAD", [Param.new("id", "", "path")]),
  Endpoint.new("/comments/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/comments/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/comments/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/comments/{id}", "OPTIONS", [Param.new("id", "", "path")]),
  # From PostController (the protected actionHidden() is not an action) action methods
  Endpoint.new("/post/index", "GET", [
    Param.new("page", "", "query"),
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/post/view", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/post/create", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("X-CSRF-Token", "", "header"),
  ]),
  Endpoint.new("/post/create", "GET", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
  ]),
  # From UserController (ActiveController) REST + action methods
  Endpoint.new("/user/index", "GET"),
  Endpoint.new("/user/view", "GET"),
  Endpoint.new("/user/create", "POST"),
  Endpoint.new("/user/update", "PUT"),
  Endpoint.new("/user/update", "PATCH"),
  Endpoint.new("/user/delete", "DELETE"),
  Endpoint.new("/user/options", "OPTIONS"),
  Endpoint.new("/user/profile", "GET", [
    Param.new("id", "", "query"),
    Param.new("session_id", "", "cookie"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/user/search", "GET", [
    Param.new("q", "", "query"),
    Param.new("tag", "", "query"),
  ]),
]

FunctionalTester.new("fixtures/php/yii/", {
  :techs     => 2,
  :endpoints => 32,
}, expected_endpoints).perform_tests
