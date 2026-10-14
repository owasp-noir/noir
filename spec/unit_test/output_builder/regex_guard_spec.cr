require "../../spec_helper"
require "../../../src/output_builder/curl"
require "../../../src/output_builder/oas3"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

# A regex location from an infra config (`kind == "regex"`) is a pattern, not
# a path: it stays in the inventory but must not become a curl command or an
# OpenAPI path.
describe "regex route guards" do
  options = {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
    "output"  => YAML::Any.new(""),
    "url"     => YAML::Any.new(""),
  }

  http = Endpoint.new("/plain/", "GET")
  regex = Endpoint.new("/(fonts|assets)/.*.(eot|ttf)", "GET")
  regex.kind = "regex"
  endpoints = [http, regex]

  it "Endpoint#regex_path? covers regex kinds and JS RegExp literals" do
    http.regex_path?.should be_false
    regex.regex_path?.should be_true
    Endpoint.new("/^\\/api\\/(\\d+)$/", "GET").regex_path?.should be_true
  end

  it "curl output skips regex routes" do
    builder = OutputBuilderCurl.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    out = builder.io.to_s
    out.should contain("/plain/")
    out.should_not contain("fonts")
  end

  it "OAS3 output skips regex routes" do
    builder = OutputBuilderOas3.new(options)
    builder.io = IO::Memory.new
    builder.print(endpoints)
    JSON.parse(builder.io.to_s)["paths"].as_h.keys.should eq(["/plain/"])
  end
end
