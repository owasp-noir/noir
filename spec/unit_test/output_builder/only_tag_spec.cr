require "../../spec_helper"
require "../../../src/output_builder/only-tag"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderOnlyTag" do
  it "print only tags from endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderOnlyTag.new(options)
    builder.io = IO::Memory.new

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
    output = builder.io.to_s

    # Verify output contains all unique tags
    lines = output.split("\n").reject(&.empty?)

    # Should have 4 unique tags (api, public, auth, sensitive)
    lines.size.should eq(4)

    # Check for presence of each tag
    lines.should contain("api")
    lines.should contain("public")
    lines.should contain("auth")
    lines.should contain("sensitive")

    # Tags should be listed in order of appearance
    lines[0].should eq("api")
    lines[1].should eq("public")
    lines[2].should eq("auth")
    lines[3].should eq("sensitive")

    # Verify no duplicate tags (api should appear only once despite being used twice)
    lines.count("api").should eq(1)
  end
end
