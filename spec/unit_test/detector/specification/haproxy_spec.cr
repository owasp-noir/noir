require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect HAProxy config" do
  options = create_test_options
  instance = Detector::Specification::Haproxy.new options

  it "detects path ACLs in haproxy.cfg and registers the path" do
    CodeLocator.instance.clear Noir::LocatorKeys::HAPROXY_SPEC
    content = "frontend web\n    acl is_api path_beg /api/\n    use_backend api if is_api\n"
    instance.detect("haproxy.cfg", content).should be_true
    CodeLocator.instance.all(Noir::LocatorKeys::HAPROXY_SPEC).should eq(["haproxy.cfg"])
  end

  it "detects anonymous path ACLs" do
    instance.detect("conf/lb.cfg", "listen api\n    http-request deny if { path_beg /internal }\n").should be_true
  end

  it "rejects configs without path matching" do
    instance.detect("haproxy.cfg", "frontend web\n    bind *:80\n    default_backend app\n").should be_false
  end

  it "rejects nginx and other .cfg files" do
    instance.detect("haproxy.conf", "server {\n  listen 80;\n  location /api { }\n}\n").should be_false
    instance.detect("setup.cfg", "[metadata]\nname = x\n").should be_false
    instance.applicable?("nginx.conf").should be_false
    instance.applicable?("docs/haproxy.md").should be_false
    instance.applicable?("deploy/haproxy.cfg.j2").should be_true
  end
end
