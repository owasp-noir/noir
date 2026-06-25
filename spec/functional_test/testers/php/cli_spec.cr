require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# Symfony Console (setName + addArgument/addOption, getenv). The fixture also
# trips php_pure (any <?php) and php_symfony (Symfony\ namespace), so 3 techs.
endpoints = [
  build.call("cli://cli_symfony", [
    Param.new("API_TOKEN", "", "env"),
  ]),
  build.call("cli://cli_symfony/app:create-user", [
    Param.new("username", "", "argument"),
    Param.new("admin", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/php/cli_symfony/", {
  :techs     => 3,
  :endpoints => endpoints.size,
}, endpoints).perform_tests
