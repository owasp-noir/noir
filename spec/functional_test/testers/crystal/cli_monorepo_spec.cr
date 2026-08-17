require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# `alpha/src/main.cr` and `beta/src/main.cr` are two unrelated programs.
# `cli_binary_name` fell back to the *immediate* parent for a `main` stem, so
# both became `cli://src` and `fetch_endpoint` merged them into one endpoint
# carrying both flag sets — with only the first file's code path to show for
# it.
endpoints = [
  build.call("cli://alpha", [Param.new("alpha-only", "", "flag")]),
  build.call("cli://beta", [Param.new("beta-only", "", "flag")]),
]

tester = FunctionalTester.new("fixtures/crystal/cli_monorepo/", {
  :endpoints => endpoints.size,
}, endpoints, {
  "only_techs" => YAML::Any.new("crystal_cli"),
})
tester.perform_tests

it "keeps each binary's flags on its own command" do
  alpha = tester.endpoints.find! { |endpoint| endpoint.url == "cli://alpha" }
  alpha.params.map(&.name).should_not contain("beta-only")

  beta = tester.endpoints.find! { |endpoint| endpoint.url == "cli://beta" }
  beta.params.map(&.name).should_not contain("alpha-only")
end
