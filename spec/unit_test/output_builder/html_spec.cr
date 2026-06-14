require "../../spec_helper"
require "file_utils"
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

  it "falls back to default HTML when template reading fails" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    # Create a directory where we expect the template file to be
    # but make it unreadable by pointing to a directory instead
    temp_dir = File.join(Dir.tempdir, "noir_test_#{Process.pid}_#{Time.utc.to_unix_ms}")
    ENV["NOIR_HOME"] = temp_dir
    Dir.mkdir_p(temp_dir)

    # Create a file that will fail to read (e.g., a directory)
    template_path = File.join(temp_dir, "report-template.html")
    Dir.mkdir(template_path)

    begin
      endpoint = Endpoint.new("/test", "GET")
      endpoint.push_param(Param.new("id", "1", "query"))
      endpoints = [endpoint]

      builder.print(endpoints)
      output = builder.io.to_s

      # Should still produce valid HTML output (fallback to default)
      output.should contain("<!DOCTYPE html>")
      output.should contain("OWASP Noir")
      output.should contain("/test")
      output.should contain("GET")
    ensure
      # Clean up
      FileUtils.rm_rf(temp_dir)
      ENV.delete("NOIR_HOME")
    end
  end

  it "renders the theme toggle and a persistence script" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    builder.print([Endpoint.new("/test", "GET")])
    output = builder.io.to_s

    # Toggle control, persistence key, and pre-paint theme init.
    output.should contain("data-action=\"toggle-theme\"")
    output.should contain("aria-pressed")
    output.should contain("noir-theme")
    output.should contain("prefers-color-scheme")
    output.should contain("[data-theme=\"dark\"]")
  end

  it "renders collapsible endpoint cards with a body" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/users", "GET")
    endpoint.push_param(Param.new("id", "1", "query"))
    builder.print([endpoint])
    output = builder.io.to_s

    output.should contain("data-action=\"toggle-card\"")
    output.should contain("aria-expanded")
    output.should contain("aria-controls=\"ep-body-0\"")
    output.should contain("id=\"ep-body-0\"")
    output.should contain("card-collapse")
    output.should contain("card-pane")
    output.should contain("chevron")
  end

  it "renders search and HTTP-method filter chips" do
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
      Endpoint.new("/users", "GET"),
      Endpoint.new("/users", "POST"),
    ]
    builder.print(endpoints)
    output = builder.io.to_s

    # Controls and per-card filter metadata.
    output.should contain("id=\"endpoint-search\"")
    output.should contain("data-filter-method=\"GET\"")
    output.should contain("data-filter-method=\"POST\"")
    output.should contain("data-endpoint")
    output.should contain("data-method=\"GET\"")
    output.should contain("data-text=")
    output.should contain("section-count")
    output.should contain("endpoint-no-results")
  end

  it "omits method chips when only one method is present" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    builder.print([Endpoint.new("/a", "GET"), Endpoint.new("/b", "GET")])
    output = builder.io.to_s

    # Search stays, but a single-verb report needs no method chips.
    # (The filter script always references the selector, so assert on the
    # rendered chip attribute form instead.)
    output.should contain("id=\"endpoint-search\"")
    output.should_not contain("data-filter-method=\"")
  end

  it "renders severity filter chips and metadata for passive findings" do
    options = {
      "debug"   => YAML::Any.new(false),
      "verbose" => YAML::Any.new(false),
      "color"   => YAML::Any.new(false),
      "nolog"   => YAML::Any.new(false),
      "output"  => YAML::Any.new(""),
    }
    builder = OutputBuilderHtml.new(options)
    builder.io = IO::Memory.new

    high = YAML.parse <<-YAML
      id: high-rule
      info:
        name: "High Rule"
        author: ["a"]
        severity: "high"
        description: "d"
        reference: ["https://example.com"]
      matchers-condition: "or"
      matchers:
        - type: "regex"
          patterns: ["x"]
          condition: "or"
      category: "secret"
      techs: ["*"]
      YAML
    medium = YAML.parse <<-YAML
      id: medium-rule
      info:
        name: "Medium Rule"
        author: ["a"]
        severity: "medium"
        description: "d"
        reference: ["https://example.com"]
      matchers-condition: "or"
      matchers:
        - type: "regex"
          patterns: ["x"]
          condition: "or"
      category: "misconfig"
      techs: ["*"]
      YAML

    results = [
      PassiveScanResult.new(PassiveScan.new(high), "a.cr", 1, "x"),
      PassiveScanResult.new(PassiveScan.new(medium), "b.cr", 2, "y"),
    ]

    builder.print([Endpoint.new("/test", "GET")], results)
    output = builder.io.to_s

    output.should contain("data-passive")
    output.should contain("data-severity=\"high\"")
    output.should contain("data-severity=\"medium\"")
    output.should contain("data-filter-severity=\"high\"")
    output.should contain("data-filter-severity=\"medium\"")
  end
end
