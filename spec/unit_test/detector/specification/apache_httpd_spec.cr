require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Apache httpd config" do
  options = create_test_options
  instance = Detector::Specification::ApacheHttpd.new options

  src = <<-CONF
    <VirtualHost *:443>
      ServerName api.example.com
      <Location /v1/users>
        ProxyPass http://users:8080/users
      </Location>
    </VirtualHost>
    CONF

  it "detects .conf with Apache directives" do
    locator = CodeLocator.instance
    locator.clear "apache-httpd-spec"

    instance.detect("sites-enabled/api.conf", src).should be_true
    locator.all("apache-httpd-spec").should eq ["sites-enabled/api.conf"]
  end

  it "detects .htaccess files" do
    htaccess = "RewriteRule ^/api/(.*)$ /v1/$1 [L,QSA]\n"
    instance.detect(".htaccess", htaccess).should be_true
  end

  it "detects Apache config templates case-insensitively" do
    locator = CodeLocator.instance
    locator.clear "apache-httpd-spec"

    instance.detect("conf/extra.conf.in", "  proxypass /api http://backend\n").should be_true
    locator.all("apache-httpd-spec").should eq ["conf/extra.conf.in"]
  end

  it "ignores directives that only appear in comments" do
    instance.detect("commented.conf", "# ProxyPass /api http://backend\n").should be_false
  end

  it "rejects .conf without Apache directives" do
    instance.detect("config.conf", "key = value\nfoo=bar\n").should be_false
  end

  it "ignores nginx.conf even if directives overlap" do
    instance.detect("nginx.conf", src).should be_false
  end
end
