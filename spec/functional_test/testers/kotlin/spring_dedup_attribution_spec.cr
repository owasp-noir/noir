require "../../func_spec.cr"

# #3082: handlers that differ only by a `params=` condition stay one endpoint
# each instead of one endpoint with every handler's params.
tester = FunctionalTester.new("fixtures/kotlin/spring_dedup_attribution/", {
  :endpoints => 3,
}, [] of Endpoint)
tester.perform_tests

it "keeps each params= handler's params on its own endpoint", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {endpoint.params.map(&.name), endpoint.details.code_paths.map(&.line)}
  end
  summary.sort_by!(&.to_s).should eq([
    {["relink"], [13]},
    {["ticket"], [10]},
    {[] of String, [7]},
  ])
end
