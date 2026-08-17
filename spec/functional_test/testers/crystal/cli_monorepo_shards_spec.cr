require "../../func_spec.cr"

build = ->(url : String, params : Array(Param)) do
  ep = Endpoint.new(url, "CLI", params)
  ep.protocol = "cli"
  ep
end

# Both shards hold a `src/tool.cr`, so both programs infer the same binary
# name. Keying the endpoint map per project keeps them apart inside the
# analyzer; the base-relative project path in the URL keeps the optimizer —
# which dedups by (method, url) and merges params — from stitching them back
# into one command.
endpoints = [
  build.call("cli://svc-a/tool", [Param.new("only-a", "", "flag")]),
  build.call("cli://svc-b/tool", [Param.new("only-b", "", "flag")]),
]

tester = FunctionalTester.new("fixtures/crystal/cli_monorepo_shards/", {
  :endpoints => endpoints.size,
}, endpoints, {
  "only_techs" => YAML::Any.new("crystal_cli"),
})
tester.perform_tests

it "does not merge two shards that infer the same binary name" do
  svc_a = tester.endpoints.find! { |endpoint| endpoint.url == "cli://svc-a/tool" }
  svc_a.params.map(&.name).should_not contain("only-b")
  svc_a.details.code_paths.map(&.path).each(&.should(contain("svc-a")))
end
