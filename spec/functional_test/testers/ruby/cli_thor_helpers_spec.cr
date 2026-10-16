require "../../func_spec.cr"

# Thor never registers `class << self` bodies, protected methods or
# Thor::Group / Thor::Actions subclasses as commands; only `serve` and
# `build` are real in thor_helpers.rb.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

thor_helpers_endpoints = [
  build.call("cli://thor_helpers/serve", [
    Param.new("port", "", "flag"),
  ]),
  build.call("cli://thor_helpers/build", [] of Param),
  # thor_nested.rb: a nested Thor::Error or Thor::Group scopes to its own body.
  build.call("cli://thor_nested/plan", [] of Param),
  build.call("cli://thor_nested/apply", [] of Param),
  build.call("cli://thor_nested/verify", [] of Param),
  build.call("cli://thor_nested/finish", [] of Param),
]

FunctionalTester.new("fixtures/ruby/cli_thor_helpers/", {
  :techs     => 1,
  :endpoints => thor_helpers_endpoints.size,
}, thor_helpers_endpoints).perform_tests
