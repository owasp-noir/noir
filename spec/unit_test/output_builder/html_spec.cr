require "../../spec_helper"
require "../../../src/output_builder/html"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"

describe "OutputBuilderHtml" do
  it "print with only endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("id", "1", "query"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify output is valid HTML and contains expected data
    output.should contain("<!DOCTYPE html>")
    output.should contain("OWASP Noir")
    output.should contain("/test")
    output.should contain("GET")
    output.should contain("id")
    output.should contain("query")
  end

  it "print with endpoints and passive results" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/api/users", "POST")
    endpoint.push_param(Param.new("username", "test", "json"))

    # Create passive scan result using the actual model structure
    scan_yaml = YAML.parse(%(
      id: test-rule
      info:
        name: "Test Rule Name"
        author: ["test-author"]
        severity: "high"
        description: "Test Description"
        reference: ["https://example.com"]
      matchers-condition: "or"
      matchers:
        - type: "regex"
          patterns: ["test"]
          condition: "or"
      category: "secret"
      techs: ["*"]
    ))
    passive_scan = PassiveScan.new(scan_yaml)
    passive_result = PassiveScanResult.new(
      passive_scan,
      "test.cr",
      10,
      "test finding"
    )

    endpoints = [endpoint]
    passive_results = [passive_result]

    builder.print(endpoints, passive_results)
    output = builder.io.to_s

    # Verify output is valid HTML and contains both endpoints and passive results
    output.should contain("<!DOCTYPE html>")
    output.should contain("/api/users")
    output.should contain("POST")
    output.should contain("username")
    output.should contain("json")
    output.should contain("Test Rule Name")
    output.should contain("test.cr")
    output.should contain("high")
  end

  it "generates summary statistics" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint1 = Endpoint.new("/users", "GET")
    endpoint2 = Endpoint.new("/users", "POST")
    endpoint2.push_param(Param.new("name", "test", "json"))
    endpoints = [endpoint1, endpoint2]

    builder.print(endpoints)
    output = builder.io.to_s

    # Check summary card content
    output.should contain("Endpoints")
    output.should contain("HTTP Methods")
    output.should contain("Parameters")
    output.should contain("Passive Findings")
  end

  it "escapes HTML special characters" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    # Create endpoint with characters that need escaping
    endpoint = Endpoint.new("/test?a=<script>", "GET")
    endpoint.push_param(Param.new("param<>", "value&\"test\"", "query"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify special characters are escaped
    output.should contain("&lt;script&gt;")
    output.should contain("param&lt;&gt;")
    output.should contain("&amp;")
  end

  it "handles empty endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoints = [] of Endpoint

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify empty state message
    output.should contain("No endpoints discovered")
    output.should contain("<!DOCTYPE html>")
  end

  it "displays code paths when available" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    details = Details.new(PathInfo.new("src/controllers/users.cr", 42))
    endpoint = Endpoint.new("/users", "GET", [] of Param, details)
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify code path is shown
    output.should contain("src/controllers/users.cr")
    output.should contain("line 42")
  end

  it "handles all HTTP methods with proper styling" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoints = [
      Endpoint.new("/test", "GET"),
      Endpoint.new("/test", "POST"),
      Endpoint.new("/test", "PUT"),
      Endpoint.new("/test", "PATCH"),
      Endpoint.new("/test", "DELETE"),
      Endpoint.new("/test", "OPTIONS"),
    ]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify method badges
    output.should contain("method-get")
    output.should contain("method-post")
    output.should contain("method-put")
    output.should contain("method-patch")
    output.should contain("method-delete")
    output.should contain("method-default")
  end

  it "handles all parameter types" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "POST")
    endpoint.push_param(Param.new("q", "search", "query"))
    endpoint.push_param(Param.new("data", "{}", "json"))
    endpoint.push_param(Param.new("field", "value", "form"))
    endpoint.push_param(Param.new("Auth", "Bearer", "header"))
    endpoint.push_param(Param.new("session", "abc", "cookie"))
    endpoint.push_param(Param.new("id", "123", "path"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify param type badges
    output.should contain("param-query")
    output.should contain("param-json")
    output.should contain("param-form")
    output.should contain("param-header")
    output.should contain("param-cookie")
    output.should contain("param-path")
  end

  it "displays tags on endpoints" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/api/admin", "GET")
    endpoint.add_tag(Tag.new("admin", "Admin endpoint", "tagger"))
    endpoint.add_tag(Tag.new("auth-required", "Requires authentication", "tagger"))
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify tags are displayed
    output.should contain("admin")
    output.should contain("auth-required")
    output.should contain("tag-badge")
  end

  it "handles websocket protocol" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/ws/chat", "GET")
    endpoint.protocol = "ws"
    endpoints = [endpoint]

    builder.print(endpoints)
    output = builder.io.to_s

    # Verify websocket protocol badge
    output.should contain("protocol-badge")
    output.should contain("ws")
  end
end
