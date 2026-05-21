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
    locator.clear "apisix-yaml"
    instance.detect("config/apisix.yaml", content)
    locator.all("apisix-yaml").should eq(["config/apisix.yaml"])
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
    locator.clear "apisix-json"
    instance.detect("config/routes.json", content)
    locator.all("apisix-json").should eq(["config/routes.json"])
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
end
