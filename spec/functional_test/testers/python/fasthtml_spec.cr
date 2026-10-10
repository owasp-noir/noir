require "../../func_spec.cr"

# FastHTML: verb-named handlers take that verb, others GET+POST; a bare
# `@rt` routes at `/<function name>`. `plugins.py` has an `@rt` that is not
# FastHTML's and must yield nothing. `main.py` also imports Starlette, which
# is detected (2 techs) but must not report these routes a second time.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/todos/{tid}", "DELETE", [Param.new("tid", "", "path")]),
  Endpoint.new("/login", "POST", [
    Param.new("username", "", "form"),
    Param.new("password", "", "form"),
  ]),
  Endpoint.new("/profile", "GET"),
  Endpoint.new("/profile", "POST"),
  # The verb-name rule needs a path: bare `@rt def post()` is GET+POST /post.
  Endpoint.new("/post", "GET"),
  Endpoint.new("/post", "POST"),
  Endpoint.new("/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/search", "POST", [Param.new("q", "", "form")]),
  Endpoint.new("/items/{item_id}", "PUT", [
    Param.new("item_id", "", "path"),
    Param.new("name", "", "form"),
  ]),
  Endpoint.new("/upload", "POST", [Param.new("file", "", "form")]),
]

FunctionalTester.new("fixtures/python/fasthtml/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
