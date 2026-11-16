require "../../func_spec.cr"
require "../../../../src/cli/inspect"

describe "NestJS TS transitive callee sink resolution", tags: "functional" do
  endpoints = [] of Endpoint

  before_all do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/nestjs_transitive_sinks/")])
    options["ai_context"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
  end

  it "reports 1-hop and 2-hop transitive sinks via query and reach, and skips ambiguous interface, cyclic and inert helpers" do
    file_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["file_io"]), false)
    file_rows.map(&.url).should eq(["/users/export"])

    sql_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["sql"]), false)
    sql_rows.map(&.url).should eq(["/users/search"])

    search_ep = endpoints.find! { |ep| ep.url == "/users/search" }
    sql_sink = search_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "sql" }
    sql_sink.path.to_s.should end_with("src/users/users.repository.ts")
    sql_sink.line.should eq(9)
    sql_sink.description.to_s.should contain("this.usersService.search -> this.usersRepository.searchByName")

    export_ep = endpoints.find! { |ep| ep.url == "/users/export" }
    file_sink = export_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "file_io" }
    file_sink.path.to_s.should end_with("src/users/users.service.ts")
    file_sink.line.should eq(10)
    file_sink.description.to_s.should contain("this.usersService.exportReport")

    reach_repo = Noir::CLI::Inspect.reach(endpoints, "src/users/users.repository.ts", nil, false)
    reach_repo.map(&.url).should eq(["/users/search"])
    reach_repo[0].via.any? { |v| v.kind == "sink" && v.name == "dataSource.query" && v.line == 9 && v.path.to_s.ends_with?("src/users/users.repository.ts") }.should be_true

    reach_svc = Noir::CLI::Inspect.reach(endpoints, "src/users/users.service.ts", nil, false)
    reach_svc.map(&.url).should eq(["/users/export"])
    reach_svc[0].via.any? { |v| v.kind == "sink" && v.name == "fs.readFileSync" && v.line == 10 && v.path.to_s.ends_with?("src/users/users.service.ts") }.should be_true

    ["/users/ambiguous", "/users/cycle", "/users/count"].each do |url|
      ep = endpoints.find! { |e| e.url == url }
      (ep.ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end
end
