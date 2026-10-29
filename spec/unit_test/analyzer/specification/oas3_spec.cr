require "../../../spec_helper"
require "file_utils"
require "../../../../src/analyzer/analyzers/specification/oas3"
require "../../../../src/analyzer/analyzers/specification/oas2"
require "../../../../src/ai_context/augmentor"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"

private def oas3_analyzer(url : String = "") : Analyzer::Specification::Oas3
  options = create_test_options
  options["url"] = YAML::Any.new(url)
  Analyzer::Specification::Oas3.new(options)
end

describe "OAS3 Analyzer" do
  it "prepends --url when an absolute server matches the target host" do
    servers = JSON.parse(%([{"url":"https://api.example.com/v1"}]))
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com/v1")
  end

  it "prepends --url to relative server paths and expands server variables" do
    servers = YAML.parse(<<-YAML
      - url: /api/{version}
        variables:
          version:
            default: v2
      YAML
    )
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com/api/v2")
  end

  it "does not root an undefaulted leading server variable as a path" do
    servers = JSON.parse(%([{"url":"{endpoint}"},{"url":"{host}/v1"},{"url":"api/{version}"}]))

    oas3_analyzer.get_base_path(servers).should eq("/api/{version}")
  end

  it "skips a server variable that is not a mapping" do
    servers = JSON.parse(%([{"url":"/api/{version}","variables":{"version":"v2"}}]))

    oas3_analyzer.get_base_path(servers).should eq("/api/{version}")
  end

  it "uses --url as the fallback base when no server matches" do
    servers = JSON.parse(%([{"url":"https://other.example.com/v1"}]))
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com")
  end

  it "ignores absolute servers with an empty host" do
    servers = JSON.parse(%([{"url":"https:///invalid"},{"url":"https://:443/also-invalid"},{"url":"https://api.example.com/v2"}]))

    oas3_analyzer.get_base_path(servers).should eq("/v2")
  end

  # With no usable `servers`, the base is `-u` itself; a trailing slash on it
  # produced `http://h//x`, which the optimizer passes through as absolute.
  it "joins a path onto a slash-terminated base with one slash" do
    dir = File.tempname("noir_oas3_slash")
    Dir.mkdir_p(dir)
    begin
      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.0
        info: {title: t, version: "1"}
        paths:
          /x:
            get:
              responses: {"200": {description: ok}}
        YAML
      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, entry)
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(dir)])
      options["url"] = YAML::Any.new("http://h/")

      Analyzer::Specification::Oas3.new(options).analyze.map(&.url).should eq(["http://h/x"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end

  it "lets path-level and operation-level servers replace the root ones" do
    dir = File.tempname("noir_oas3_scoped_servers")
    Dir.mkdir_p(dir)
    begin
      yaml = <<-YAML
        openapi: 3.0.3
        info: {title: t, version: "1"}
        servers: [{url: https://api.example.com/v2}]
        paths:
          /pets:
            servers: [{url: https://files.example.com/upload}]
            get:
              responses: {"200": {description: ok}}
            post:
              servers: [{url: /ops}]
              responses: {"200": {description: ok}}
          /owners:
            servers: [{url: "files.example.com"}]
            get:
              responses: {"200": {description: ok}}
        YAML
      File.write(File.join(dir, "openapi.yaml"), yaml)
      File.write(File.join(dir, "openapi.json"), YAML.parse(yaml).to_json)
      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, File.join(dir, "openapi.yaml"))
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_JSON, File.join(dir, "openapi.json"))
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(dir)])

      expected = [{"GET", "/upload/pets"}, {"POST", "/ops/pets"}, {"GET", "/v2/owners"}]
      Analyzer::Specification::Oas3.new(options).analyze.map { |e| {e.method, e.url} }.should eq(expected + expected)
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end

  # The effective `security` (operation-level, else global) is an auth guard;
  # `[]` and an empty `{}` alternative admit anonymous callers.
  it "turns the effective security requirement into an auth guard" do
    dir = File.tempname("noir_oas3_security")
    Dir.mkdir_p(dir)
    begin
      yaml = <<-YAML
        openapi: 3.0.3
        info: {title: Items API, version: 1.0.0}
        security:
          - bearerAuth: []
        components:
          securitySchemes:
            bearerAuth: {type: http, scheme: bearer}
            apiKey: {type: apiKey, in: header, name: X-API-Key}
        paths:
          /items:
            post:
              responses: {'201': {description: created}}
          /items/{item_id}:
            delete:
              security:
                - bearerAuth: []
                  apiKey: []
                - apiKey: []
              parameters:
                - {name: item_id, in: path, required: true, schema: {type: string}}
              responses: {'204': {description: deleted}}
          /public/feedback:
            post:
              security: []
              responses: {'200': {description: ok}}
          /maybe:
            post:
              security:
                - {}
                - bearerAuth: []
              responses: {'200': {description: ok}}
          /undefined:
            get:
              security:
                - nosuch: []
              responses: {'200': {description: ok}}
          /partly-undefined:
            get:
              security:
                - nosuch: []
                - bearerAuth: []
                  nosuch: []
                - apiKey: []
              responses: {'200': {description: ok}}
        YAML
      File.write(File.join(dir, "openapi.yaml"), yaml)
      File.write(File.join(dir, "openapi.json"), YAML.parse(yaml).to_json)
      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, File.join(dir, "openapi.yaml"))
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_JSON, File.join(dir, "openapi.json"))
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(dir)])

      endpoints = Analyzer::Specification::Oas3.new(options).analyze
      endpoints.size.should eq(12)
      endpoints.each do |endpoint|
        details = endpoint.details
        details.technology = "oas3"
        endpoint.details = details
      end
      tags = endpoints.map { |e| {e.url, e.tags.map { |t| {t.name, t.description} }} }.uniq!
      tags.should eq([
        {"/items", [{"auth", "Protected by OAS security bearerAuth (inherited from the spec's root security)"}]},
        {"/items/{item_id}", [{"auth", "Protected by OAS security bearerAuth + apiKey or apiKey"}]},
        {"/public/feedback", [{"anonymous", "OAS security admits anonymous callers"}]},
        {"/maybe", [{"anonymous", "OAS security admits anonymous callers"}]},
        # A scheme the document never defines guards nothing.
        {"/undefined", [] of Tuple(String, String)},
        {"/partly-undefined", [{"auth", "Protected by OAS security apiKey"}]},
      ])

      signals = NoirAIContext.apply(endpoints[0, 4]).to_h do |endpoint|
        context = endpoint.ai_context.should_not be_nil
        {endpoint.url, context.guards.map(&.kind) + context.signals.map(&.kind).select(&.in?("guard_absence", "idor_review"))}
      end
      signals["/items"].should eq(["auth_guard"])
      signals["/items/{item_id}"].should eq(["auth_guard"])
      signals["/public/feedback"].should eq(["guard_absence"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end

  it "reads Swagger 2 security the same way" do
    CodeLocator.instance.clear_all
    fixture = "./spec/functional_test/fixtures/specification/oas2_security/doc.yml"
    CodeLocator.instance.push(Noir::LocatorKeys::SWAGGER_YAML, fixture)
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/specification/oas2_security")])

    tags = Analyzer::Specification::Oas2.new(options).analyze.map { |e| {e.method, e.url, e.tags.map(&.description)} }
    tags.should eq([
      {"GET", "/v1/items", ["Protected by OAS security ApiKeyHeader (inherited from the spec's root security)"]},
      {"POST", "/v1/items", ["Protected by OAS security BasicAuth"]},
      {"GET", "/v1/public", ["OAS security admits anonymous callers"]},
      {"GET", "/v1/search", ["Protected by OAS security ApiKeyQuery"]},
    ])
  ensure
    CodeLocator.instance.clear_all
  end
end
