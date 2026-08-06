require "../../spec_helper"
require "../../../src/models/passive_scan"
require "../../../src/output_builder/common"
require "../../../src/output_builder/oas3"
require "../../../src/output_builder/postman"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

# `config_initializer` seeds every option key for CLI runs, so the builders got
# away with reading `@options["url"]` / `@options["status_codes"]` by hard
# index. Anything constructing a builder with only the keys it cares about —
# specs here, library consumers — hit a KeyError instead, and inconsistently:
# oas2 and only-url already read the same options through `[]?` while oas3,
# postman and common did not.
describe "Output builders with a partial options hash" do
  minimal = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(true),
    "output"  => YAML::Any.new(""),
  }

  endpoint = Endpoint.new("/api/users/{id}", "GET")
  endpoint.push_param(Param.new("id", "", "path"))
  endpoint.push_param(Param.new("q", "noir", "query"))

  it "renders plain output without the display-toggle keys" do
    builder = OutputBuilderCommon.new(minimal)
    builder.io = IO::Memory.new

    builder.print([endpoint])

    builder.io.to_s.should contain("/api/users/{id}?q=noir")
    # No `url` option means no probing ran, so no status code is shown.
    builder.io.to_s.should_not contain("[error]")
  end

  it "falls back to the default server url in oas3" do
    builder = OutputBuilderOas3.new(minimal)
    builder.io = IO::Memory.new

    builder.print([endpoint])

    JSON.parse(builder.io.to_s)["servers"][0]["url"].as_s.should eq("http://localhost")
  end

  it "falls back to the default baseUrl in postman" do
    builder = OutputBuilderPostman.new(minimal)
    builder.io = IO::Memory.new

    builder.print([endpoint])
    variables = JSON.parse(builder.io.to_s)["variable"].as_a

    variables[0]["key"].as_s.should eq("baseUrl")
    variables[0]["value"].as_s.should eq("http://localhost")
  end
end
