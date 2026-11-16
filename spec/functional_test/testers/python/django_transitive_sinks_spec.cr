require "../../func_spec.cr"
require "../../../../src/cli/inspect"

describe "Python transitive callee sink resolution", tags: "functional" do
  endpoints = [] of Endpoint

  before_all do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/django_transitive_sinks/")])
    options["ai_context"] = YAML::Any.new(true)
    options["include_callee"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
  end

  it "reports 1-hop and 2-hop transitive sinks via query and reach, and skips ambiguous, cyclic and inert helpers" do
    cmd_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["command_exec"]), false)
    cmd_rows.map { |r| "#{r.method} #{r.url}" }.sort!.should eq(["GET /export/", "POST /export/"])

    sql_rows = Noir::CLI::Inspect.query(endpoints, Noir::CLI::Inspect::Filters.new(sinks: ["sql"]), false)
    sql_rows.map(&.url).should eq(["/report/"])

    report_ep = endpoints.find! { |ep| ep.url == "/report/" }
    sql_sink = report_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "sql" }
    sql_sink.path.to_s.should end_with("app/repo.py")
    sql_sink.line.should eq(6)
    sql_sink.description.to_s.should contain("build_report -> repo.find_rows")

    export_ep = endpoints.find! { |ep| ep.method == "POST" && ep.url == "/export/" }
    cmd_sink = export_ep.ai_context.not_nil!.sinks.find! { |s| s.kind == "command_exec" }
    cmd_sink.path.to_s.should end_with("app/services.py")
    cmd_sink.line.should eq(7)
    cmd_sink.description.to_s.should contain("services.run_export")

    reach_repo = Noir::CLI::Inspect.reach(endpoints, "app/repo.py", nil, false)
    reach_repo.map(&.url).should eq(["/report/"])
    reach_repo[0].via.any? { |v| v.kind == "sink" && v.name == "cursor.execute" && v.line == 6 && v.path.to_s.ends_with?("app/repo.py") }.should be_true

    reach_services = Noir::CLI::Inspect.reach(endpoints, "app/services.py", nil, false)
    reach_services.find! { |r| r.method == "POST" && r.url == "/export/" }.via.map(&.to_text).any?(&.starts_with?("sink:subprocess.run")).should be_true

    ["/ambiguous/", "/cycle/", "/ping/"].each do |url|
      ep = endpoints.find! { |e| e.url == url }
      (ep.ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end
end
