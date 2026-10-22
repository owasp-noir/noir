require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
    Param.new("verbose", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
    Param.new("arg0", "", "argument"),
  ]),
]
FunctionalTester.new("fixtures/perl/cli_getopt/", {:techs => 1, :endpoints => endpoints.size}, endpoints).perform_tests

descriptive_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("name", "", "flag"),
    Param.new("help", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
    Param.new("arg0", "", "argument"),
  ]),
]
FunctionalTester.new("fixtures/perl/cli_getopt_long_descriptive/", {:techs => 1, :endpoints => descriptive_endpoints.size}, descriptive_endpoints).perform_tests

moox_endpoints = [
  build.call("cli://myapp", [
    Param.new("verbose", "", "flag"),
    Param.new("name", "", "flag"),
    Param.new("API_TOKEN", "", "env"),
  ]),
]
FunctionalTester.new("fixtures/perl/cli_moox_options/", {:techs => 1, :endpoints => moox_endpoints.size}, moox_endpoints).perform_tests

# Regression: an unrelated bareword sub named `option` (nothing to do with
# MooX::Options) must NOT leak a bogus "timeout" flag when the file never
# does `use MooX::Options`. Only the real GetOptions("port=i") flag should
# surface.
moox_fp_endpoints = [
  build.call("cli://tool", [
    Param.new("port", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/perl/cli_moox_options_fp/", {:techs => 1, :endpoints => moox_fp_endpoints.size}, moox_fp_endpoints).perform_tests

# Regression: Getopt::Long::Descriptive suffix modifiers (!, +) must be
# stripped from the reported flag name instead of leaking as "verbose!" /
# "count+".
descriptive_modifiers_endpoints = [
  build.call("cli://tool", [
    Param.new("verbose", "", "flag"),
    Param.new("count", "", "flag"),
  ]),
]
FunctionalTester.new("fixtures/perl/cli_describe_options_modifiers_fp/", {:techs => 1, :endpoints => descriptive_modifiers_endpoints.size}, descriptive_modifiers_endpoints).perform_tests
