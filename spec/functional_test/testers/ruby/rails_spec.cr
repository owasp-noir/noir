require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/secret.html", "GET"),
  Endpoint.new("/posts", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/posts/1", "GET", [
    Param.new("X-API-KEY", "", "header"),
    # `params.fetch(:x)` and `params.dig(:top, ...)` read top-level keys too.
    Param.new("page", "", "query"),
    Param.new("filter", "", "query"),
  ]),
  Endpoint.new("/posts", "POST", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PUT", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "PATCH", [
    Param.new("title", "", "json"),
    Param.new("context", "", "json"),
  ]),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/posts/1/search", "QUERY"),
  Endpoint.new("/search", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/filter", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "GET", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/both", "QUERY", [
    Param.new("user_name", "", "cookie"),
    Param.new("login", "", "cookie"),
    Param.new("discount", "", "cookie"),
  ]),
  Endpoint.new("/articles", "POST", [
    Param.new("title", "", "form"),
    Param.new("body", "", "form"),
    Param.new("alpha", "", "form"),
    Param.new("beta", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PUT", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/articles/1", "PATCH", [
    Param.new("one", "", "form"),
    Param.new("tags", "", "form"),
    Param.new("meta", "", "form"),
    Param.new("cat", "", "form"),
  ]),
  Endpoint.new("/up", "GET"),
  Endpoint.new("/service-worker", "GET"),
  Endpoint.new("/manifest", "GET"),
]

tester = FunctionalTester.new("fixtures/ruby/rails/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reads fetch on bare params only, not on a *_params hash", tags: "functional" do
  show = tester.app.endpoints.find { |endpoint| endpoint.url == "/posts/1" && endpoint.method == "GET" }
  show.should_not be_nil
  show.not_nil!.params.map(&.name).should_not contain("theme")
end
