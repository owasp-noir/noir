require "../../func_spec.cr"

# #3082: the dedup merged handlers that only share method + URL and unioned
# their params. `params=` handlers stay one endpoint each, the two apps'
# `/` routes stay apart, and the Feign client's params stay off the served
# `/v1/quote`.
tester = FunctionalTester.new("fixtures/java/spring_dedup_attribution/", {
  :endpoints => 6,
}, [] of Endpoint)
tester.perform_tests

it "keeps per-handler params and code paths", tags: "functional" do
  summary = tester.endpoints.map do |endpoint|
    {
      "#{endpoint.method} #{endpoint.url}",
      endpoint.params.map(&.name),
      endpoint.details.code_paths.map { |code_path| "#{File.basename(code_path.path)}:#{code_path.line}" },
    }
  end
  summary.sort!.should eq([
    {"ANY /", [] of String, ["RootController.java:7"]},
    {"ANY /", ["banner"], ["GateController.java:16"]},
    {"GET /gate/reset", [] of String, ["GateController.java:7"]},
    {"GET /gate/reset", ["relink"], ["GateController.java:13"]},
    {"GET /gate/reset", ["ticket"], ["GateController.java:10"]},
    {"GET /v1/quote", ["sym"], ["QuoteController.java:7", "QuoteClient.java:8"]},
  ])
  tester.endpoints.none?(&.internal).should be_true
end
