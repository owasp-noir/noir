require "../../func_spec.cr"

# The `cac` evidence marker is word-bounded (so cache/cacheName no longer pass
# the gate); a real `import cac from 'cac'` CLI must still be detected.
build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

cac_endpoints = [
  build.call("cli://cacdemo", [
    Param.new("verbose", "", "flag"),
  ]),
  build.call("cli://cacdemo/serve", [
    Param.new("port", "", "flag"),
  ]),
]

FunctionalTester.new("fixtures/javascript/cli_cac/", {
  :techs     => 1,
  :endpoints => cac_endpoints.size,
}, cac_endpoints).perform_tests
