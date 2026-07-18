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
    builder.io = IO::Memory.new

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

    # Verify the mindmap structure without Markdown tags
    output.should contain("mindmap")
    output.should_not contain("```mermaid")
    output.should_not contain("```")
    output.should contain("root((API))")
    output.should contain("GET")
    output.should contain("  headers")
    output.should contain("    x_api_key")
    output.should contain("api")
    output.should contain("  users")
    output.should contain("    POST")
    output.should contain("      body")
    output.should contain("        email")
    output.should contain("        username")
    output.should contain("    GET")
    # A query param lands in its own `query` group, not lumped into `body`.
    output.should contain("      query")
    output.should contain("        limit")
  end

  it "prints hierarchical paths with grouped parameters, websocket, and path parameters" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.io = IO::Memory.new

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
    endpoint6.protocol = "ws"

    endpoint7 = Endpoint.new("/app/{user_id}", "GET")
    endpoint7.push_param(Param.new("user_id", "", "path"))

    endpoints = [endpoint1, endpoint2, endpoint3, endpoint4, endpoint5, endpoint6, endpoint7]
    builder.print(endpoints)
    output = builder.io.to_s

    # Verify hierarchical structure with grouped parameters and path parameters
    output.should contain("mindmap")
    output.should_not contain("```mermaid")
    output.should_not contain("```")
    output.should contain("root((API))")
    output.should contain("app")
    output.should contain("  data")
    output.should contain("    GET")
    output.should contain("      headers")
    output.should contain("        auth_token")
    output.should contain("  users")
    output.should contain("    POST")
    output.should contain("      body")
    output.should contain("        param1")
    output.should contain("        param2")
    # The path parameter shows up twice, on purpose and complementarily:
    # as a `param_*` segment node (its position in the URL hierarchy)...
    output.should contain("  param_user_id")
    output.should contain("    GET")
    # ...and, named, inside the endpoint's own `path` group (not `body`).
    output.should contain("      path")
    output.should contain("        user_id")
    output.should contain("public")
    output.should contain("  images")
    output.should contain("    GET")
    output.should contain("    GET")
    output.should contain("  path_1_html")
    output.should contain("    GET")
    output.should contain("      cookies")
    output.should contain("        session_id")
    output.should contain("socket")
    # A bare ` websocket` word, not `[websocket]`: brackets are mindmap
    # node-shape syntax and would hide the "GET" method on render.
    output.should contain("  GET websocket")
    output.should_not contain("[websocket]")
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
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    endpoint.push_param(Param.new("test_param", "", "query"))
    endpoints = [endpoint]

    # Create passive scan result
    scan_yaml = YAML.parse <<-YAML
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
      YAML
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

    # Verify mindmap structure
    output.should contain("mindmap")
    output.should_not contain("```mermaid")
    output.should_not contain("```")
    output.should contain("root((API))")
    output.should contain("test")
    output.should contain("  GET")
    output.should contain("    query")
    output.should contain("      test_param")

    # Verify passive scan findings are rendered as a branch
    output.should contain("  passive")
    output.should contain("test_rule")
    output.should contain("high")
    output.should contain("test_cr_10")
  end

  it "normalizes framework path-parameter notations to param_* segments" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.io = IO::Memory.new

    # Every framework spells path parameters differently; all four must
    # collapse to a `param_*` segment so the notation never leaks into the
    # node id (`:id` used to become `_id`, `*` used to become `_`).
    e1 = Endpoint.new("/items/:id", "GET")       # colon (Sinatra/Rails/Express)
    e2 = Endpoint.new("/files/*", "GET")         # bare splat / wildcard
    e3 = Endpoint.new("/blob/*path", "GET")      # named splat
    e4 = Endpoint.new("/users/{user_id}", "GET") # brace (OpenAPI)

    builder.print([e1, e2, e3, e4])
    output = builder.io.to_s

    # Each is a second-level segment (6-space indent) under its parent.
    output.should contain("      param_id")
    output.should contain("      param_wildcard")
    output.should contain("      param_path")
    output.should contain("      param_user_id")
  end

  it "keeps same-named params in separate location groups (no overwrite)" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderMermaid.new(options)
    builder.io = IO::Memory.new

    # A `token` in the query string and a `token` in the JSON body are two
    # distinct attack-surface inputs. The old single "body" bucket keyed by
    # name collapsed them into one node; each must now survive under its
    # own location group.
    endpoint = Endpoint.new("/auth", "POST")
    endpoint.push_param(Param.new("token", "", "query"))
    endpoint.push_param(Param.new("token", "", "json"))

    builder.print([endpoint])
    output = builder.io.to_s

    output.should contain("      query")
    output.should contain("      body")
    output.should contain("        token")
    # Both groups plus the two members => exactly two `token` leaf nodes.
    output.scan("token").size.should eq(2)
  end
end
