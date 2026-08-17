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

    # Line 3: Endpoint outside code span is HTML/backslash escaped; param inside code span keeps literal HTML/backslashes
    expected_line_2 = "| GET\\\\POST /&lt;script&gt;alert(1)&lt;/script&gt; | http | `<i>html</i> (query)`  |"
    lines[3].should eq(expected_line_2)
  end

  it "preserves literal <, >, and \\ inside code spans while escaping pipes" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/api/test", "GET")
    endpoint.push_param(Param.new("c<ook>ie", "val", "cookie"))
    endpoint.push_param(Param.new("path\\to", "val", "path"))
    endpoint.push_param(Param.new("foo|bar", "val", "query"))

    builder.print([endpoint])
    cell = builder.io.to_s.split("\n")[2]

    cell.should contain("`c<ook>ie (cookie)`")
    cell.should contain("`path\\to (path)`")
    cell.should contain("`foo\\|bar (query)`")
  end

  it "keeps the code span intact when a param name contains a backtick" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    # A single backtick closed the span early and the remainder of the row ran
    # on as loose text.
    endpoint = Endpoint.new("/search", "POST")
    endpoint.push_param(Param.new("md`tick", "v", "query"))
    # Two adjacent backticks need a three-backtick fence.
    endpoint.push_param(Param.new("run``two", "v", "query"))
    # Leading/trailing backticks need the space pad CommonMark strips.
    endpoint.push_param(Param.new("`edge", "v", "query"))

    builder.print([endpoint])
    cell = builder.io.to_s.split("\n")[2]

    cell.should contain("``md`tick (query)``")
    cell.should contain("```run``two (query)```")
    cell.should contain("`` `edge (query) ``")
  end

  it "escapes a backtick in a text cell so it cannot open a span" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    builder.print([Endpoint.new("/a`b`c", "GET")])
    cell = builder.io.to_s.split("\n")[2]

    cell.should eq("| GET /a\\`b\\`c | http | - |")
  end

  it "renders a placeholder for an endpoint with no params" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMarkdownTable.new(options)
    builder.io = IO::Memory.new

    # The `-` placeholder sat behind a `params.nil?` check that could never be
    # true, so this rendered as an empty cell.
    builder.print([Endpoint.new("/no-params", "GET")])

    builder.io.to_s.split("\n")[2].should eq("| GET /no-params | http | - |")
  end
end
