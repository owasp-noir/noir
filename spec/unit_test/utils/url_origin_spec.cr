require "spec"
require "../../../src/utils/url_origin"

describe Noir::UrlOrigin do
  it "extracts scheme, host and port" do
    Noir::UrlOrigin.of("https://api.example.com/v1/users").should eq("https://api.example.com")
    Noir::UrlOrigin.of("http://127.0.0.1:8080/health").should eq("http://127.0.0.1:8080")
  end

  it "treats the scheme's default port as absent" do
    Noir::UrlOrigin.of("https://api.example.com:443/x").should eq(Noir::UrlOrigin.of("https://api.example.com/x"))
    Noir::UrlOrigin.of("http://api.example.com:80/x").should eq(Noir::UrlOrigin.of("http://api.example.com/x"))
  end

  it "compares case-insensitively on scheme and host" do
    Noir::UrlOrigin.of("HTTPS://API.Example.COM/x").should eq(Noir::UrlOrigin.of("https://api.example.com/y"))
  end

  it "distinguishes host, port and scheme" do
    target = Noir::UrlOrigin.of("https://api.example.com")
    target.should_not eq(Noir::UrlOrigin.of("https://evil.example.com"))
    target.should_not eq(Noir::UrlOrigin.of("https://api.example.com:8443"))
    target.should_not eq(Noir::UrlOrigin.of("http://api.example.com"))
    # A lookalike that only shares a prefix — a plain `starts_with?` check
    # would call this the same host.
    target.should_not eq(Noir::UrlOrigin.of("https://api.example.com.evil.test"))
  end

  it "accepts the scheme-less authority form -u allows" do
    Noir::UrlOrigin.of("example.com/api").should eq("http://example.com")
    Noir::UrlOrigin.of("example.com:8080").should eq("http://example.com:8080")
  end

  it "returns nil when there is no host to compare" do
    Noir::UrlOrigin.of(nil).should be_nil
    Noir::UrlOrigin.of("").should be_nil
    Noir::UrlOrigin.of("   ").should be_nil
    Noir::UrlOrigin.of("/api/users").should be_nil
    Noir::UrlOrigin.of("/{tenant}/users").should be_nil
  end
end
