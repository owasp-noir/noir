require "../../func_spec.cr"

# Regression test: `get_req_header(` / `conn,` / `"x-api-token"` / `)`
# (mix format's wrap of a long call) was missed by the per-line param
# scan; a commented-out wrapped read must still not count.
FunctionalTester.new("fixtures/elixir/plug_wrapped_params/", {
  :techs     => 1,
  :endpoints => 1,
}, [
  Endpoint.new("/secured", "GET", [
    Param.new("x-api-token", "", "header"),
    Param.new("q", "", "query"),
  ]),
]).perform_tests

describe "Plug wrapped param negatives", tags: "functional" do
  it "does not read a param out of a commented-out wrapped call" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/elixir/plug_wrapped_params/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    app.endpoints.flat_map(&.params).map(&.name).should_not contain("x-ghost")
  end
end
