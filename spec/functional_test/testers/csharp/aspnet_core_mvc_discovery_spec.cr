require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/catalog", "GET"),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/named", "GET"),
  Endpoint.new("/inventory", "POST"),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/actions/live", "GET"),
  Endpoint.new("/actions/live", "POST"),
  Endpoint.new("/actions/documented", "GET"),
]

tester = FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_discovery/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "ASP.NET Core MVC controller discovery", tags: "functional" do
  it "finds controller attributes and suffixes independently of filenames" do
    %w[/catalog /status /named].each do |path|
      tester.endpoints.any? { |endpoint| endpoint.url == path }.should be_true
    end
  end

  it "inherits controller attributes, not controller name suffixes" do
    %w[/inventory /ping].each do |path|
      tester.endpoints.any? { |endpoint| endpoint.url == path }.should be_true
    end
    tester.endpoints.any? { |endpoint| endpoint.url == "/unmarked" }.should be_false
  end

  it "excludes non-controller, non-public, abstract, generic and nested classes" do
    %w[/helper /disabled /excluded /internal /abstract /generic /nested].each do |path|
      tester.endpoints.any? { |endpoint| endpoint.url == path }.should be_false
    end
  end

  it "consumes NonAction on private and protected helpers without suppressing the next action" do
    tester.endpoints.select { |endpoint| endpoint.url == "/actions/live" }.map(&.method).sort!.should eq %w[GET POST]
    tester.endpoints.any? { |endpoint| endpoint.url == "/actions/excluded" }.should be_false
  end

  it "ignores line, block and documentation comments while preserving source lines" do
    tester.endpoints.any?(&.url.includes?("comment")).should be_false
    documented = tester.endpoints.find! { |endpoint| endpoint.url == "/actions/documented" }
    documented.details.code_paths.first.line.should eq 38
  end
end
