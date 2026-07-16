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

  it "detects nginx include fragments without server blocks" do
    instance.detect("h5bp/location/security_file_access.conf", <<-CONF).should be_true
      location ~* /\\.(?!well-known\\/) {
          deny all;
      }
      CONF
  end

  it "detects nginx templates" do
    instance.detect("nginx.tmpl", <<-CONF).should be_true
      {{ if .Enabled }}
      server {
          location /debug {
              return 200;
          }
      }
      {{ end }}
      CONF
  end

  it "rejects .conf without nginx-shape directives" do
    instance.detect("config.conf", "key = value\nfoo = bar\n").should be_false
  end

  it "detects location assembled by template-action removal" do
    # `strip_template_actions` splices `loc{{ … }}ation` back together, so
    # the SHAPE_GUARD fast path must not reject template files on the raw
    # (marker-less) content.
    instance.detect("weird.tmpl", "loc{{ .X }}ation /v1 { proxy_pass http://up; }\n").should be_true
  end

  it "rejects nginx-looking words inside comments" do
    instance.detect("comment.conf", <<-CONF).should be_false
      # server {
      #   location /commented-out {
      #   }
      # }
      CONF
  end
end
