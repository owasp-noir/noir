require "../../func_spec.cr"
require "../../../../src/cli/inspect"

describe "Express JS transitive callee sink resolution", tags: "functional" do
  endpoints = [] of Endpoint

  before_all do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_transitive_sinks/")])
    options["ai_context"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
  end

  it "reports 1-hop and 2-hop transitive sinks via query and reach, and skips ambiguous, cyclic and inert helpers" do
    file_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["file_io"]), false)
    file_rows.map(&.url).should eq(["/files/read"])

    sql_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["sql"]), false)
    sql_rows.map(&.url).should eq(["/files/report"])

    read_ep = endpoints.find! { |ep| ep.url == "/files/read" }
    file_sink = read_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "file_io" }
    file_sink.path.to_s.should end_with("src/services/fileService.js")
    file_sink.line.should eq(6)
    file_sink.description.to_s.should contain("fileService.read")

    report_ep = endpoints.find! { |ep| ep.url == "/files/report" }
    sql_sink = report_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "sql" }
    sql_sink.path.to_s.should end_with("src/repos/reportRepo.js")
    sql_sink.line.should eq(5)
    sql_sink.description.to_s.should contain("reportService.generate -> reportRepo.fetchRows")

    reach_file = Noir::CLI::Inspect.reach(endpoints, "src/services/fileService.js", nil, false)
    reach_file.map(&.url).should eq(["/files/read"])
    reach_file[0].via.any? { |v| v.kind == "sink" && v.name == "fs.readFile" && v.line == 6 && v.path.to_s.ends_with?("src/services/fileService.js") }.should be_true

    reach_repo = Noir::CLI::Inspect.reach(endpoints, "src/repos/reportRepo.js", nil, false)
    reach_repo.map(&.url).should eq(["/files/report"])
    reach_repo[0].via.any? { |v| v.kind == "sink" && v.name == "pool.query" && v.line == 5 && v.path.to_s.ends_with?("src/repos/reportRepo.js") }.should be_true

    ["/files/ambiguous", "/files/cycle", "/files/slug"].each do |url|
      ep = endpoints.find! { |e| e.url == url }
      (ep.ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end
end
