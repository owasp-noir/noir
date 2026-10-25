require "../../func_spec.cr"

# Function views read like Django runs them: an f-string route reads the
# module string it interpolates, a view reading the raw body answers POST,
# a bound form reads its declared fields (bases included), a Pydantic model
# validating the body names its fields, and a function the view hands
# `request` to contributes its reads, scoped to the `request.method`
# branch that calls it.
expected_endpoints = [
  Endpoint.new("/login/", "GET", [Param.new("account-closed", "", "query")]),
  Endpoint.new("/login/", "POST", [
    Param.new("email", "", "form"),
    Param.new("password", "", "form"),
    Param.new("account-closed", "", "query"),
  ]),
  Endpoint.new("/ping/<uuid:code>/<int:exitstatus>", "GET", [Param.new("user-agent", "", "header")]),
  Endpoint.new("/ping/<uuid:code>/<int:exitstatus>", "POST", [Param.new("user-agent", "", "header")]),
  Endpoint.new("/slug/<slug:slug>", "GET", [Param.new("user-agent", "", "header")]),
  Endpoint.new("/slug/<slug:slug>", "POST", [Param.new("user-agent", "", "header")]),
  Endpoint.new("/checks/", "GET", [Param.new("tag", "", "query")]),
  Endpoint.new("/checks/", "POST", [Param.new("name", "", "json"), Param.new("tags", "", "json")]),
  Endpoint.new("/search/", "GET", [Param.new("q", "", "query"), Param.new("start", "", "query")]),
]

FunctionalTester.new("fixtures/python/django_function_views/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Django function view helper scoping", tags: "functional" do
  it "keeps a branch helper's reads on its verb" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/django_function_views/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    get = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/checks/" }
    get.params.map(&.name).should_not contain("name")
    post = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/checks/" }
    post.params.map(&.name).should_not contain("tag")
  end
end
