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
    locator.clear Noir::LocatorKeys::ENVOY_YAML

    instance.detect("envoy.yaml", yaml).should be_true
    locator.all(Noir::LocatorKeys::ENVOY_YAML).should eq ["envoy.yaml"]
  end

  it "detects envoy json route config" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::ENVOY_JSON

    json = %({"virtual_hosts":[{"name":"backend","domains":["*"]}]})
    instance.detect("envoy.json", json).should be_true
    locator.all(Noir::LocatorKeys::ENVOY_JSON).should eq ["envoy.json"]
  end

  it "detects a bootstrap config that nests route_config under a listener filter" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::ENVOY_YAML

    bootstrap = <<-YAML
      static_resources:
        listeners:
          - name: listener_0
            filter_chains:
              - filters:
                  - name: envoy.filters.network.http_connection_manager
                    typed_config:
                      route_config:
                        virtual_hosts:
                          - name: local_service
                            domains: ["*"]
                            routes:
                              - match:
                                  prefix: "/"
      YAML

    instance.detect("envoy.yaml", bootstrap).should be_true
    locator.all(Noir::LocatorKeys::ENVOY_YAML).should eq ["envoy.yaml"]
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
