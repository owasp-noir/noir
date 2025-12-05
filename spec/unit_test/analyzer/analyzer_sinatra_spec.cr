require "../../spec_helper"
require "../../../src/analyzer/analyzers/ruby/sinatra.cr"

describe "mapping_to_path" do
  options = create_test_options
  instance = Analyzer::Ruby::Sinatra.new(options)

  it "line_to_param - param[]" do
    line = "param['id']"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - params[]" do
    line = "params['id']"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - headers[]" do
    line = "headers['x-token']"
    instance.line_to_param(line).name.should eq("x-token")
  end

  it "line_to_param - request.env" do
    line = "request.env[\"x-token\"]"
    instance.line_to_param(line).name.should eq("x-token")
  end
end
