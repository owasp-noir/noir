require "../../spec_helper"
require "../../../src/output_builder/mermaid"
require "../../../src/models/endpoint"
require "../../../src/models/passive_scan"
require "../../../src/utils/utils"

describe "OutputBuilderMermaid" do
  it "prints simple endpoints with grouped parameters" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.set_io IO::Memory.new

    endpoint1 = Endpoint.new("/", "GET")
    endpoint1.push_param(Param.new("x-api-key", "", "header"))

    endpoint2 = Endpoint.new("/api/users", "POST")
    endpoint2.push_param(Param.new("username", "", "json"))
    endpoint2.push_param(Param.new("email", "", "json"))

    endpoint3 = Endpoint.new("/api/users", "GET")
    endpoint3.push_param(Param.new("limit", "", "query"))

    endpoints = [endpoint1, endpoint2, endpoint3]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify the mindmap structure
    output.should contain("mindmap")
    output.should contain("root((/))")
    output.should contain("GET /")
    output.should contain("  headers")
    output.should contain("    x_api_key")
    output.should contain("api")
    output.should contain("  users")
    output.should contain("    POST /api/users")
    output.should contain("      body")
    output.should contain("        email")
    output.should contain("        username")
    output.should contain("    GET /api/users")
    output.should contain("      body")
    output.should contain("        limit")
  end

  it "prints hierarchical paths with grouped parameters and websocket" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.set_io IO::Memory.new

    endpoint1 = Endpoint.new("/app/data", "GET")
    endpoint1.push_param(Param.new("auth_token", "", "header"))

    endpoint2 = Endpoint.new("/app/users", "POST")
    endpoint2.push_param(Param.new("param1", "", "form"))
    endpoint2.push_param(Param.new("param2", "", "form"))

    endpoint3 = Endpoint.new("/public/images/1.png", "GET")
    endpoint4 = Endpoint.new("/public/images/2.png", "GET")
    endpoint5 = Endpoint.new("/public/1.html", "GET")
    endpoint5.push_param(Param.new("session_id", "", "cookie"))

    endpoint6 = Endpoint.new("/socket", "GET")
    endpoint6.protocol = "websocket"

    endpoints = [endpoint1, endpoint2, endpoint3, endpoint4, endpoint5, endpoint6]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify hierarchical structure with grouped parameters
    output.should contain("mindmap")
    output.should contain("root((/))")
    output.should contain("app")
    output.should contain("  data")
    output.should contain("    GET /app/data")
    output.should contain("      headers")
    output.should contain("        auth_token")
    output.should contain("  users")
    output.should contain("    POST /app/users")
    output.should contain("      body")
    output.should contain("        param1")
    output.should contain("        param2")
    output.should contain("public")
    output.should contain("  images")
    output.should contain("    GET /public/images/1.png")
    output.should contain("    GET /public/images/2.png")
    output.should contain("  path_1_html")
    output.should contain("    GET /public/1.html")
    output.should contain("      cookies")
    output.should contain("        session_id")
    output.should contain("socket")
    output.should contain("  GET /socket [websocket]")
  end

  it "prints with endpoints and passive results" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.set_io IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("test_param", "", "query"))
    endpoints = [endpoint]

    # Create passive scan result
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
    passive_results = [passive_result]

    builder.print(endpoints, passive_results)
    output = builder.io.to_s

    # Verify mindmap structure, ignoring passive results
    output.should contain("mindmap")
    output.should contain("root((/))")
    output.should contain("test")
    output.should contain("  GET /test")
    output.should contain("    body")
    output.should contain("      test_param")
  end
end
