require "../../spec_helper"
require "../../../src/analyzer/analyzers/crystal/kemal.cr"

describe "mapping_to_path" do
  options = create_test_options
  instance = Analyzer::Crystal::Kemal.new(options)

  it "line_to_param - env.params.query" do
    line = "env.params.query[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.params.json" do
    line = "env.params.json[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.params.body" do
    line = "env.params.body[\"id\"]"
    instance.line_to_param(line).name.should eq("id")
  end

  it "line_to_param - env.response.headers[]" do
    line = "env.request.headers[\"x-token\"]"
    instance.line_to_param(line).name.should eq("x-token")
  end
end
