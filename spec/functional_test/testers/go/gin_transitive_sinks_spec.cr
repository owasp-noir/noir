require "../../func_spec.cr"
require "../../../../src/cli/inspect"

describe "Go transitive callee sink resolution", tags: "functional" do
  endpoints = [] of Endpoint

  before_all do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/gin_transitive_sinks/")])
    options["ai_context"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
  end

  it "reports 1-hop and 2-hop transitive sinks via query and reach, and skips ambiguous interface, cyclic and inert helpers" do
    cmd_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["command_exec"]), false)
    cmd_rows.map(&.url).should eq(["/export"])

    sql_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["sql"]), false)
    sql_rows.map(&.url).should eq(["/users/search"])

    search_ep = endpoints.find! { |ep| ep.url == "/users/search" }
    sql_sink = search_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "sql" }
    sql_sink.path.to_s.should end_with("internal/repo/user.go")
    sql_sink.line.should eq(17)
    sql_sink.description.to_s.should contain("h.svc.Search -> s.repo.SearchByName")

    export_ep = endpoints.find! { |ep| ep.url == "/export" }
    cmd_sink = export_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "command_exec" }
    cmd_sink.path.to_s.should end_with("internal/service/user.go")
    cmd_sink.line.should eq(36)
    cmd_sink.description.to_s.should contain("h.svc.RunExport")

    reach_repo = Noir::CLI::Inspect.reach(endpoints, "internal/repo/user.go", nil, false)
    reach_repo.map(&.url).should eq(["/users/search"])
    reach_repo[0].via.any? { |v| v.kind == "sink" && v.name == "db.Query" && v.line == 17 && v.path.to_s.ends_with?("internal/repo/user.go") }.should be_true

    reach_service = Noir::CLI::Inspect.reach(endpoints, "internal/service/user.go", nil, false)
    reach_service.map(&.url).should eq(["/export"])
    reach_service[0].via.any? { |v| v.kind == "sink" && v.name == "exec" && v.line == 36 && v.path.to_s.ends_with?("internal/service/user.go") }.should be_true

    ["/ambiguous", "/cycle", "/health"].each do |url|
      ep = endpoints.find! { |e| e.url == url }
      (ep.ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end
end
