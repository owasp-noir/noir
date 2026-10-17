require "../../func_spec.cr"

expected_endpoints = [
  # #3087: DTO declared in a file not named after it (dto/Requests.kt).
  Endpoint.new("/zoo/feed", "POST", [
    Param.new("animalName", "", "json"),
    Param.new("grams", "", "json"),
  ]),
  # #3088: method-less @RequestMapping maps every verb.
  Endpoint.new("/zoo/proxy/**", "ANY"),
  # #3089: constants after / inside a nested object, positional bare constants.
  Endpoint.new("/zoo/lang", "GET", [Param.new("x-widget-lang", "", "header")]),
  Endpoint.new("/zoo/after-nested", "GET", [Param.new("x-inner", "", "header")]),
  Endpoint.new("/zoo/x", "GET"),
  # Several declarations on one line; an unresolvable constant keeps the argument name.
  Endpoint.new("/zoo/one-a", "GET", [Param.new("x-top-one", "", "header")]),
  Endpoint.new("/zoo/one-b", "GET", [Param.new("x-deep-one", "", "header")]),
  Endpoint.new("/zoo/unresolved", "GET", [Param.new("m", "", "header")]),
  Endpoint.new("/zoo/cb", "POST", [
    Param.new("X-Widget-Token", "", "header"),
    Param.new("q", "", "query"),
  ]),
  # #3090: overloads, params= conditions, collection bodies, nullable id, by lazy.
  Endpoint.new("/zoo/{sid}/hints", "GET", [Param.new("x-a", "", "header")]),
  Endpoint.new("/zoo/hints", "POST", [
    Param.new("x-a", "", "header"),
    Param.new("items", "", "json"),
    Param.new("note", "", "json"),
  ]),
  Endpoint.new("/zoo/owners", "DELETE", [
    Param.new("ownerKey", "", "query"),
    Param.new("label", "", "query"),
  ]),
  Endpoint.new("/zoo/ids", "POST", [Param.new("ids", "", "json")]),
  Endpoint.new("/zoo/blob", "PUT", [Param.new("data", "", "json")]),
  Endpoint.new("/zoo/search", "GET", [
    Param.new("id", "", "query"),
    Param.new("species", "", "query"),
  ]),
  Endpoint.new("/zoo/ping", "POST", [Param.new("who", "", "json")]),
]

FunctionalTester.new("fixtures/kotlin/spring_param_gaps/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Kotlin Spring param gaps: no extra params", tags: "functional" do
  it "emits exactly the expected params per endpoint" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/spring_param_gaps/")])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    expected_endpoints.each do |expected|
      actual = app.endpoints.find! { |ep| ep.method == expected.method && ep.url == expected.url }
      actual.params.reject { |p| p.param_type == "path" }.map { |p| {p.name, p.param_type} }
        .should eq(expected.params.map { |p| {p.name, p.param_type} })
    end
  end
end
