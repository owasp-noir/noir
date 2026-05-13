require "../../spec_helper"
require "../../../src/analyzer/analyzers/crystal/amber.cr"

describe "amber callee extraction" do
  it "extracts callees from single-line controller actions" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    instance = Analyzer::Crystal::Amber.new(options)

    temp_dir = File.tempname("amber_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.cr")

    File.write(temp_file, <<-CRYSTAL)
      class ApplicationController < Amber::Controller::Base
        def index; payload = HomeService.build; json payload; end
      end

      Amber::Server.configure do
        routes :web do
          get "/", ApplicationController, :index
        end
      end
      CRYSTAL

    endpoints = instance.analyze_file(temp_file)
    endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/" }
    endpoint.should_not be_nil
    if endpoint
      endpoint.callees.map(&.name).should contain("HomeService.build")
      endpoint.callees.map(&.name).should contain("json")
      endpoint.callees.find { |c| c.name == "HomeService.build" }.try(&.line).should eq(2)
      endpoint.callees.find { |c| c.name == "json" }.try(&.line).should eq(2)
    end

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end
end
