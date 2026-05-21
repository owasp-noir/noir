require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Nginx config" do
  options = create_test_options
  instance = Detector::Specification::Nginx.new options

  src = <<-CONF
    server {
        listen 443 ssl;
        server_name api.example.com;
        location /v1/users { proxy_pass http://users; }
    }
    CONF

  it "detects nginx.conf with server/location blocks" do
    locator = CodeLocator.instance
    locator.clear "nginx-spec"

    instance.detect("nginx.conf", src).should be_true
    locator.all("nginx-spec").should eq ["nginx.conf"]
  end

  it "detects .conf fragments" do
    instance.detect("sites-enabled/api.conf", src).should be_true
  end

  it "rejects .conf without nginx-shape directives" do
    instance.detect("config.conf", "key = value\nfoo = bar\n").should be_false
  end
end
