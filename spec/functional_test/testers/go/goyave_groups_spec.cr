require "../../func_spec.cr"

# Regression test: goyave's fluent router builder chains configuration
# methods that return the same `*Router` (`subrouter.Group().SetMeta(...)`).
# The `.SetMeta(...)` tail must be peeled so the assigned subrouter binds
# to the parent prefix; otherwise every route under it falls back to `/`.
# Mirrors go-goyave/goyave-blog-example.
#
# Coverage:
#   - GET /articles/                — direct subrouter route (callee
#                                     resolves through the controller
#                                     method to `listArticles`).
#   - GET /articles/{slug}          — path param under the prefix.
#   - POST /articles/               — `Group().SetMeta(...)` child inherits
#                                     `/articles`.
#   - PATCH/DELETE /articles/{articleID}
#                                   — nested `Group()` child also inherits
#                                     `/articles`; the `{id:regex}` form is
#                                     normalized to `{articleID}`.
expected_endpoints = [
  Endpoint.new("/articles/", "GET").tap do |ep|
    ep.push_callee(Callee.new("listArticles"))
  end,
  Endpoint.new("/articles/{slug}", "GET", [
    Param.new("slug", "", "path"),
  ]),
  Endpoint.new("/articles/", "POST"),
  Endpoint.new("/articles/{articleID}", "PATCH", [
    Param.new("articleID", "", "path"),
  ]),
  Endpoint.new("/articles/{articleID}", "DELETE", [
    Param.new("articleID", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/go/goyave_groups/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
