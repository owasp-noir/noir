require "../../spec_helper"
require "../../../src/output_builder/only-tag"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyTag" do
  it "print only tags from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(true),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyTag.new(options)

    # Create endpoints with tags
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.add_tag(Tag.new("api", "API endpoint", "tagger1"))
    endpoint1.add_tag(Tag.new("public", "Public endpoint", "tagger1"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.add_tag(Tag.new("auth", "Authentication required", "tagger2"))
    endpoint2.add_tag(Tag.new("api", "API endpoint", "tagger1"))

    # Add param with tags
    param = Param.new("token", "123", "header")
    param.add_tag(Tag.new("sensitive", "Sensitive data", "tagger3"))
    endpoint2.push_param(param)

    endpoints = [endpoint1, endpoint2]
    builder.print(endpoints)
  end
end
