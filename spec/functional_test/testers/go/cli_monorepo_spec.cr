require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# One `go.mod`, two commands. `go_binary_name` named every file in the module
# after the module, so `services/alpha/cmd` and `services/beta/cmd` both
# became `cli://mono` and their flag sets merged. Each `package main`
# directory is its own binary; library packages still take the module name so
# the cross-file merge this analyzer is built around keeps working.
endpoints = [
  build.call("cli://alpha", [
    Param.new("alpha-only-flag", "", "flag"),
    Param.new("alpha-extra-flag", "", "flag"),
  ]),
  build.call("cli://beta", [Param.new("beta-only-flag", "", "flag")]),
]

tester = FunctionalTester.new("fixtures/go/cli_monorepo/", {
  :endpoints => endpoints.size,
}, endpoints, {
  "only_techs" => YAML::Any.new("go_cli"),
})
tester.perform_tests

it "keeps each command's flags on its own binary" do
  alpha = tester.endpoints.find! { |endpoint| endpoint.url == "cli://alpha" }
  alpha.params.map(&.name).should_not contain("beta-only-flag")
end

it "records every file that contributed to a command" do
  alpha = tester.endpoints.find! { |endpoint| endpoint.url == "cli://alpha" }
  paths = alpha.details.code_paths.map { |code_path| File.basename(code_path.path) }
  paths.should contain("main.go")
  paths.should contain("flags.go")
end
