require "../../func_spec.cr"

# Regression test: a param read wrapped over lines (`params.fetch(` /
# `:q2` / `)`) was missed by the per-line param regexes; a commented-out
# wrapped read must still not count.
expected_endpoints = [
  Endpoint.new("/one", "GET", [
    Param.new("q1", "", "query"),
    Param.new("HTTP_X_H1", "", "header"),
  ]),
  Endpoint.new("/split", "GET", [
    Param.new("q2", "", "query"),
    Param.new("q3", "", "query"),
    Param.new("HTTP_X_H2", "", "header"),
    Param.new("c2", "", "cookie"),
  ]),
]

FunctionalTester.new("fixtures/ruby/sinatra_wrapped_params/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Sinatra wrapped param negatives", tags: "functional" do
  it "does not read a param out of a commented-out wrapped call" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/ruby/sinatra_wrapped_params/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.flat_map(&.params).map(&.name).should_not contain("ghost")
  end
end
