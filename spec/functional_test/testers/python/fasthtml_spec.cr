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
  # `APIRouter(prefix=...)` routes in products.py.
  Endpoint.new("/products/all", "GET"),
  Endpoint.new("/products/details", "GET", [Param.new("pid", "", "query")]),
  Endpoint.new("/products/details", "POST", [Param.new("pid", "", "form")]),
  Endpoint.new("/products/{pid}/buy", "POST", [
    Param.new("pid", "", "path"),
    Param.new("qty", "", "form"),
  ]),
]

# `@app.ws` / `@ar.ws` are WebSocket routes; message fields are not params.
ws = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "GET", params)
  ep.protocol = "ws"
  ep
end
expected_endpoints << ws.call("/ws/{room}", [Param.new("room", "", "path")])
expected_endpoints << ws.call("/products/live", [] of Param)

FunctionalTester.new("fixtures/python/fasthtml/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
