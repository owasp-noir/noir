require "../../spec_helper"
require "../../../src/output_builder/markdown_table"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderMarkdownTable" do
  it "print endpoints as markdown table" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    # Create endpoints with various parameters and methods
    endpoint1 = Endpoint.new("/test", "GET")
    endpoint1.push_param(Param.new("id", "1", "query"))
    endpoint1.push_param(Param.new("session", "abc123", "cookie"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "test", "json"))
    endpoint2.push_param(Param.new("x-api-key", "key123", "header"))

    endpoint3 = Endpoint.new("/api/products", "PUT")
    endpoint3.push_param(Param.new("product_id", "123", "path"))

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output has markdown table structure and expected content
    lines = output.split("\n")

    # Check table headers
    lines[0].should eq("| Endpoint | Protocol | Params |")
    lines[1].should contain("| -") # Separator line

    # Check table content for each endpoint
    lines[2].should contain("GET /test")
    lines[2].should contain("http")
    lines[2].should contain("id (query)")
    lines[2].should contain("session (cookie)")

    lines[3].should contain("POST /api/users")
    lines[3].should contain("username (json)")
    lines[3].should contain("x-api-key (header)")

    lines[4].should contain("PUT /api/products")
    lines[4].should contain("product_id (path)")
  end

  it "escapes special characters in markdown table" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test|url", "GET|POST")
    endpoint.protocol = "http|https"
    endpoint.push_param(Param.new("param|name", "val", "query|type"))

    # Add HTML and backslash test case
    endpoint_html = Endpoint.new("/<script>alert(1)</script>", "GET\\POST")
    endpoint_html.push_param(Param.new("<i>html</i>", "val", "query"))

    builder.print([endpoint, endpoint_html])
    output = builder.io.to_s
    lines = output.split("\n")

    # Verify content is escaped
    # Line 2: | GET\|POST /test\|url | http\|https | `param\|name (query\|type)`  |
    expected_line_1 = "| GET\\|POST /test\\|url | http\\|https | `param\\|name (query\\|type)`  |"
    lines[2].should eq(expected_line_1)

    # Line 3: | GET\\POST /&lt;script&gt;alert(1)&lt;/script&gt; | http | `&lt;i&gt;html&lt;/i&gt; (query)`  |
    expected_line_2 = "| GET\\\\POST /&lt;script&gt;alert(1)&lt;/script&gt; | http | `&lt;i&gt;html&lt;/i&gt; (query)`  |"
    lines[3].should eq(expected_line_2)
  end
end
