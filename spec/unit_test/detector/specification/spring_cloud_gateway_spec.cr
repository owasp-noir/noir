require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Spring Cloud Gateway config" do
  options = create_test_options
  instance = Detector::Specification::SpringCloudGateway.new options

  it "detects nested YAML routes and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::SPRING_CLOUD_GATEWAY_SPEC
    content = <<-YAML
      spring:
        cloud:
          gateway:
            routes:
              - id: users
                predicates:
                  - Path=/api/users/**
      YAML
    instance.detect("src/main/resources/application.yml", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::SPRING_CLOUD_GATEWAY_SPEC).should eq(["src/main/resources/application.yml"])
  end

  it "detects dotted YAML keys in a profile file" do
    content = "spring.cloud.gateway.routes:\n  - id: a\n    predicates: [ \"Path=/a\" ]\n"
    instance.detect("application-prod.yaml", content).should be_true
  end

  it "detects properties routes" do
    content = "spring.cloud.gateway.server.webflux.routes[0].predicates[0]=Path=/a/**\n"
    instance.detect("application.properties", content).should be_true
  end

  it "rejects a plain Spring Boot config" do
    instance.detect("application.yml", "server:\n  port: 8080\nspring:\n  application:\n    name: app\n").should be_false
  end

  it "ignores files that are not Spring Boot config" do
    instance.applicable?("gateway.yml").should be_false
    instance.applicable?("application.yml").should be_true
    instance.applicable?("bootstrap-dev.properties").should be_true
  end
end
