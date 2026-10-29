require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/apisix"
require "../../../../src/models/code_locator"

describe "Detect APISIX route config" do
  options = create_test_options
  instance = Detector::Specification::Apisix.new options

  it "detects APISIX YAML route config with upstream_id" do
    content = <<-YAML
      routes:
        - id: 1
          uri: /v1/users
          methods: [GET]
          upstream_id: 1
      YAML

    instance.detect("apisix.yaml", content).should be_true
  end

  it "detects APISIX JSON route config with plugins" do
    content = <<-JSON
      {
        "routes": [
          {
            "id": 2,
            "uris": ["/admin", "/admin/*"],
            "methods": ["GET"],
            "plugins": { "key-auth": {} }
          }
        ]
      }
      JSON

    instance.detect("routes.json", content).should be_true
  end

  it "registers APISIX yaml files in CodeLocator" do
    content = <<-YAML
      routes:
        - uri: /api/*
          methods: ["*"]
          plugins:
            cors: {}
      YAML

    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::APISIX_YAML
    instance.detect("config/apisix.yaml", content)
    locator.all(Noir::LocatorKeys::APISIX_YAML).should eq(["config/apisix.yaml"])
  end

  it "registers APISIX json files in CodeLocator" do
    content = <<-JSON
      {
        "routes": [
          {
            "uri": "/api/*",
            "methods": ["*"],
            "upstream_id": 7
          }
        ]
      }
      JSON

    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::APISIX_JSON
    instance.detect("config/routes.json", content)
    locator.all(Noir::LocatorKeys::APISIX_JSON).should eq(["config/routes.json"])
  end

  it "rejects generic routes yaml without APISIX-specific keys" do
    content = <<-YAML
      routes:
        - uri: /v1/users
          methods: [GET]
      YAML

    instance.detect("routes.yaml", content).should be_false
  end

  it "rejects files without routes array/object structure" do
    content = <<-JSON
      {
        "openapi": "3.0.0",
        "paths": {}
      }
      JSON

    instance.detect("openapi.json", content).should be_false
  end

  it "detects an inline upstream mapping" do
    content = <<-YAML
      routes:
        - uri: /hello
          methods: [GET]
          upstream:
            nodes:
              "127.0.0.1:1980": 1
            type: roundrobin
      YAML

    instance.detect("apisix.yaml", content).should be_true
  end

  it "detects JSON routes with an inline upstream or a service_id" do
    upstream = %({"routes":[{"uri":"/hello","upstream":{"type":"roundrobin"}}]})
    service = %({"routes":[{"uris":["/orders/*"],"service_id":1}]})
    scalar = %({"routes":[{"uri":"/hello","upstream":"http://example.com"}]})

    instance.detect("routes.json", upstream).should be_true
    instance.detect("routes.json", service).should be_true
    instance.detect("routes.json", scalar).should be_false
  end

  it "detects a route that only names service_id" do
    content = <<-YAML
      routes:
        - uris: [/orders/*]
          service_id: 1
      YAML

    instance.detect("apisix.yaml", content).should be_true
  end

  it "rejects a scalar upstream and a prose mention of the word" do
    scalar = <<-YAML
      routes:
        - uri: /hello
          upstream: http://example.com
      YAML
    prose = <<-YAML
      routes:
        - uri: /hello
          description: the upstream is down
      YAML

    instance.detect("routes.yaml", scalar).should be_false
    instance.detect("notes.yaml", prose).should be_false
  end

  it "rejects OpenAPI-ish content whose markers only appear as substrings" do
    # "security" contains "uri" as a bare substring; the word-bounded guard
    # must not let a large spec like this reach the full JSON parse.
    content = <<-JSON
      {
        "swagger": "2.0",
        "paths": {"/routes": {"get": {"security": [], "plugins-doc": true}}}
      }
      JSON

    instance.detect("swagger.json", content).should be_false
  end
end
