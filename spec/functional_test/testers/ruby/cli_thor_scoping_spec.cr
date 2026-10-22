require "../../func_spec.cr"

# `private` / `protected` end at the class (or `class << self`) that wrote
# them, and a started Thor::Group is a one-command program; an unstarted
# Thor::Group (library_generator.rb) reports nothing.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

thor_scoping_endpoints = [
  build.call("cli://thor_scoping/serve", [] of Param),
  build.call("cli://thor_scoping/build", [] of Param),
  build.call("cli://gen", [
    Param.new("name", "", "argument"),
    Param.new("force", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/ruby/cli_thor_scoping/", {
  :techs     => 1,
  :endpoints => thor_scoping_endpoints.size,
}, thor_scoping_endpoints).perform_tests
