require "../../func_spec.cr"

# A PocketBase route names its handler (`sub.GET("/{key}", backupDownload)`,
# a method value `api.download`), and the handler's request reads are the
# route's params, wherever the handler is declared. A helper no route
# names keeps its read to itself.
expected_endpoints = [
  Endpoint.new("/api/files/{collection}/{recordId}/{filename}", "GET", [
    Param.new("token", "", "query"),
    Param.new("thumb", "", "query"),
  ]),
  Endpoint.new("/api/files/{key}", "GET", [
    Param.new("token", "", "query"),
    Param.new("X-Backup-Key", "", "header"),
  ]),
  Endpoint.new("/api/files/token", "POST"),
  Endpoint.new("/hello", "GET", [Param.new("name", "", "query")]),
  Endpoint.new("/braces", "GET", [Param.new("open", "", "query")]),
  Endpoint.new("/next", "GET", [Param.new("after", "", "query")]),
  Endpoint.new("/one", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/outer", "GET", [Param.new("shallow", "", "query")]),
  Endpoint.new("/inner", "GET", [Param.new("deep", "", "query")]),
]

tester = FunctionalTester.new("fixtures/go/pocketbase_handlers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names each route's handler and keeps a helper's read off every route", tags: "functional" do
  root = "./spec/functional_test/fixtures/go/pocketbase_handlers"
  download = tester.app.endpoints.find! { |ep| ep.url == "/api/files/{collection}/{recordId}/{filename}" }
  download.handler.try(&.name).should eq("api.download")
  backup = tester.app.endpoints.find! { |ep| ep.url == "/api/files/{key}" }
  backup.handler.should eq(Handler.new("backupDownload", "#{root}/apis/backup.go", 6))
  tester.app.endpoints.flat_map(&.params).map(&.name).should_not contain("unrelated")
  token = tester.app.endpoints.find! { |ep| ep.url == "/api/files/token" }
  token.params.should be_empty
  # Each closure keeps its own reads.
  {"/braces" => %w[open], "/next" => %w[after], "/outer" => %w[shallow], "/inner" => %w[deep]}.each do |url, names|
    tester.app.endpoints.find! { |ep| ep.url == url }.params.map(&.name).should eq(names)
  end
end
