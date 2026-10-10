require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  # Action arguments bind by name; `id` is already the path param.
  Endpoint.new("/users/:id", "POST", [
    Param.new("id", "", "path"),
    Param.new("name", "", "form"),
    Param.new("email", "", "form"),
  ]),
  Endpoint.new("/users", "GET", [Param.new("page", "", "query")]),
  # `WS` is a websocket upgrade; the `revel.ServerWebSocket` argument is injected.
  Endpoint.new("/feed", "GET"),
  Endpoint.new("/public/*filepath", "GET", [Param.new("filepath", "", "path")]),
  # `*` accepts any verb; the dynamic route is emitted once, not expanded.
  Endpoint.new("/:controller/:action", "ANY", [
    Param.new("controller", "", "path"),
    Param.new("action", "", "path"),
  ]),
  # `module:testrunner` is skipped and `play_app/conf/routes` has no Revel
  # code beside it, so neither contributes.
]

FunctionalTester.new("fixtures/go/revel/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Revel catch-all tag", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "marks the dynamic :controller.:action route" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/revel/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.find! { |ep| ep.method == "ANY" }.tags.map(&.name).should eq ["catch-all"]
    app.endpoints.find! { |ep| ep.url == "/feed" }.protocol.should eq "ws"
  end
end
