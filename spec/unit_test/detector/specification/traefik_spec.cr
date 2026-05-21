require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect Traefik dynamic config" do
  options = create_test_options
  instance = Detector::Specification::Traefik.new options

  it "detects traefik dynamic yaml" do
    content = <<-YAML
      http:
        routers:
          api:
            rule: "Host(`api.example.com`) && PathPrefix(`/v1`)"
      YAML

    instance.detect("traefik.yml", content).should be_true
  end

  it "detects ingressroute yaml" do
    content = <<-YAML
      apiVersion: traefik.io/v1alpha1
      kind: IngressRoute
      spec:
        routes:
          - match: Host(`example.com`) && Path(`/admin`)
      YAML

    instance.detect("ingressroute.yaml", content).should be_true
  end

  it "detects traefik toml" do
    content = <<-TOML
      [http.routers.api]
      rule = "Host(`api.example.com`) && PathPrefix(`/v1`)"
      TOML

    instance.detect("traefik.toml", content).should be_true
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "traefik-spec"
    instance.detect("traefik.yaml", "http:\n  routers:\n    api:\n      rule: \"Path(`/v1`)\"")
    locator.all("traefik-spec").should eq(["traefik.yaml"])
  end

  it "rejects unrelated yaml" do
    instance.detect("app.yaml", "version: '3.9'\nservices:\n  app:\n    image: test").should be_false
  end
end
