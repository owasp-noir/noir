require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Kamal deploy config" do
  options = create_test_options
  instance = Detector::Specification::Kamal.new options

  deploy = <<-YAML
    service: my-app
    image: acme/my-app
    servers:
      web:
        - 192.168.0.1
    proxy:
      ssl: true
      host: app.example.com
      app_port: 3000
    YAML

  it "detects a config/deploy.yml with service, image and proxy" do
    locator = CodeLocator.instance
    locator.clear "kamal-spec"

    instance.detect("config/deploy.yml", deploy).should be_true
    locator.all("kamal-spec").should eq ["config/deploy.yml"]
  end

  it "detects a config that only declares servers (no proxy)" do
    src = <<-YAML
      service: my-app
      image: acme/my-app
      servers:
        - 192.168.0.1
      YAML
    instance.detect("config/deploy.staging.yml", src).should be_true
  end

  it "rejects Docker Compose files (plural services, no top-level image)" do
    compose = <<-YAML
      services:
        web:
          image: nginx:latest
          ports:
            - "80:80"
      YAML
    instance.detect("docker-compose.yml", compose).should be_false
  end

  it "rejects YAML that lacks servers and proxy" do
    src = <<-YAML
      service: my-app
      image: acme/my-app
      registry:
        username: acme
      YAML
    instance.detect("deploy.yml", src).should be_false
  end

  it "ignores unrelated extensions" do
    instance.detect("deploy.json", deploy).should be_false
  end
end
