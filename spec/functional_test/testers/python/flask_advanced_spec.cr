require "../../func_spec.cr"

expected_endpoints = [
  # App-level shortcut decorators
  Endpoint.new("/app-get", "GET"),
  Endpoint.new("/app-post", "POST"),

  # Blueprint shortcut decorators
  Endpoint.new("/api/bp-get", "GET"),
  Endpoint.new("/api/bp-post", "POST", [Param.new("data", "", "form")]),
  Endpoint.new("/api/bp-put", "PUT"),
  Endpoint.new("/api/bp-patch", "PATCH"),
  Endpoint.new("/api/bp-delete", "DELETE"),

  # MethodView - UserAPI
  Endpoint.new("/api/users", "GET", [Param.new("username", "", "query")]),
  Endpoint.new("/api/users", "POST", [Param.new("username", "", "form"), Param.new("email", "", "json")]),
  Endpoint.new("/api/users/<int:user_id>", "GET", [Param.new("username", "", "query")]),
  Endpoint.new("/api/users/<int:user_id>", "PUT"),
  Endpoint.new("/api/users/<int:user_id>", "DELETE"),

  # MethodView - ItemAPI
  Endpoint.new("/api/items", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items", "POST", [Param.new("name", "", "json")]),

  # request.get_json()
  Endpoint.new("/api/get-json", "POST", [Param.new("action", "", "json")]),

  # Nested blueprint registration
  Endpoint.new("/mounted/child/reports/<int:report_id>", "GET", [Param.new("mode", "", "query")]),

  # MethodView - ItemAPI (inferred methods, no explicit methods= arg)
  Endpoint.new("/api/items-inferred", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-inferred", "POST", [Param.new("name", "", "json")]),

  # flask.views.View dispatch_request with class-level methods
  Endpoint.new("/api/reports-view", "GET", [Param.new("owner", "", "query")]),
  Endpoint.new("/api/reports-view", "POST", [Param.new("title", "", "json")]),

  # MethodView - AsyncAPI (async def)
  Endpoint.new("/api/async", "GET", [Param.new("category", "", "query")]),
  Endpoint.new("/api/async", "POST", [Param.new("title", "", "json")]),

  # add_url_rule with rule= keyword (not first positional)
  Endpoint.new("/api/items-kwarg", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-kwarg", "POST", [Param.new("name", "", "json")]),

  # add_url_rule with positional view_func (3rd arg)
  Endpoint.new("/api/items-positional", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-positional", "POST", [Param.new("name", "", "json")]),

  # add_url_rule without endpoint name (view_func as keyword)
  Endpoint.new("/api/items-no-endpoint", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-no-endpoint", "POST", [Param.new("name", "", "json")]),

  # add_url_rule with tuple methods syntax
  Endpoint.new("/api/items-tuple", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-tuple", "POST", [Param.new("name", "", "json")]),

  # add_url_rule split across lines
  Endpoint.new("/api/items-multiline", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/items-multiline", "POST", [Param.new("name", "", "json")]),

  # add_url_rule with function views
  Endpoint.new("/api/registered-search", "GET", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),
  Endpoint.new("/api/registered-create", "POST", [
    Param.new("name", "", "json"),
  ]),
  Endpoint.new("/api/external-search", "GET", [
    Param.new("term", "", "query"),
    Param.new("X-Trace-Id", "", "header"),
  ]),

  # Explicit Flask static route
  Endpoint.new("/assets/*", "GET"),
]

FunctionalTester.new("fixtures/python/flask_advanced/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
