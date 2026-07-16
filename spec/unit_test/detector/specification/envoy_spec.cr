require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Envoy route config" do
  options = create_test_options
  instance = Detector::Specification::Envoy.new options

  yaml = <<-YAML
    route_config:
      name: local_route
      virtual_hosts:
        - name: backend
          domains: ["*"]
          routes:
            - match:
                prefix: /v1/users
    YAML

  it "detects envoy yaml route config" do
    locator = CodeLocator.instance
    locator.clear "envoy-yaml"

    instance.detect("envoy.yaml", yaml).should be_true
    locator.all("envoy-yaml").should eq ["envoy.yaml"]
  end

  it "detects envoy json route config" do
    locator = CodeLocator.instance
    locator.clear "envoy-json"

    json = %({"virtual_hosts":[{"name":"backend","domains":["*"]}]})
    instance.detect("envoy.json", json).should be_true
    locator.all("envoy-json").should eq ["envoy.json"]
  end

  it "rejects yaml without virtual_hosts/domains markers" do
    instance.detect("app.yaml", "version: '3.9'\nservices:\n  app:\n    image: test").should be_false
  end

  it "rejects invalid yaml that carries the markers" do
    instance.detect("broken.yaml", "virtual_hosts:\n  - domains: [broken").should be_false
  end

  it "rejects invalid json that carries the markers" do
    instance.detect("broken.json", %({"virtual_hosts":[{"domains":)).should be_false
  end
end
