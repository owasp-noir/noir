require "../../spec_helper"
require "http/server"
require "uri"
require "yaml"
require "../../../src/deliver/send_proxy"
require "../../../src/models/endpoint"

# Stub HTTP forward proxy on a random port. A real forward proxy
# rewrites the absolute-URI request line into a downstream request,
# but for assertion purposes we only need to confirm that send_proxy
# routed the request through this server's address.
private class StubProxy
  getter requests : Array(NamedTuple(method: String, target: String, body: String))
  getter address : Socket::IPAddress

  def initialize
    @requests = [] of NamedTuple(method: String, target: String, body: String)
    @server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      @requests << {
        method: context.request.method,
        # In proxy mode, the request line carries the absolute URI.
        target: context.request.resource,
        body:   body,
      }
      context.response.status_code = 200
      context.response.print "ok"
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url : String
    "http://#{@address.address}:#{@address.port}"
  end

  def close
    @server.close
  end
end

private def base_deliver_options(proxy_url : String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(".")])
  options["probe_via"] = YAML::Any.new(proxy_url)
  options
end

describe SendWithProxy do
  it "routes a GET request through the configured proxy" do
    proxy = StubProxy.new
    begin
      ep = Endpoint.new("http://example.test/api/ping", "GET")
      sender = SendWithProxy.new(base_deliver_options(proxy.url))
      sender.run([ep])

      proxy.requests.size.should eq(1)
      req = proxy.requests.first
      req[:method].should eq("GET")
      # The proxy sees the absolute target URL even though
      # example.test never resolves — the proxy itself accepted the
      # connection, which is all we need to confirm routing.
      req[:target].should contain("http://example.test/api/ping")
    ensure
      proxy.close
    end
  end

  it "routes a POST with form body through the proxy" do
    proxy = StubProxy.new
    begin
      ep = Endpoint.new("http://example.test/login", "POST")
      ep.params << Param.new("user", "alice", "form")

      sender = SendWithProxy.new(base_deliver_options(proxy.url))
      sender.run([ep])

      req = proxy.requests.first
      req[:method].should eq("POST")
      req[:body].should contain("user=alice")
    ensure
      proxy.close
    end
  end

  it "expands synthetic ANY endpoints before routing through the proxy" do
    proxy = StubProxy.new
    begin
      ep = Endpoint.new("http://example.test/wildcard", "ANY")
      sender = SendWithProxy.new(base_deliver_options(proxy.url))
      sender.run([ep])

      methods = proxy.requests.map(&.[:method]).sort!
      methods.should eq(WILDCARD_HTTP_METHODS.sort)
      methods.includes?("ANY").should be_false
    ensure
      proxy.close
    end
  end

  it "swallows proxy connection errors so the batch finishes" do
    # Point at a port nobody's listening on. send_proxy must rescue
    # the connect failure and not hang the WaitGroup.
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(".")])
    options["probe_via"] = YAML::Any.new("http://127.0.0.1:1")

    ep = Endpoint.new("http://example.test/", "GET")
    sender = SendWithProxy.new(options)
    # Just asserting "doesn't raise" — the run call must return
    # cleanly so noir keeps running after a misconfigured proxy.
    sender.run([ep])
  end

  # Crest's `set_proxy!` bails out unless it receives both a host and a
  # port, and then sends the request *directly to the target* — silently,
  # and (because proxy delivery forces an insecure TLS context) with
  # certificate verification off and any --probe-header credentials
  # attached. These two pin the refusal: no proxy, no traffic.
  describe ".resolve_proxy_target" do
    it "resolves a well-formed proxy URL" do
      SendWithProxy.resolve_proxy_target("http://127.0.0.1:8080").should eq({"127.0.0.1", 8080})
      SendWithProxy.resolve_proxy_target("https://proxy.local:3128").should eq({"proxy.local", 3128})
    end

    it "refuses a portless URL rather than letting Crest drop the proxy" do
      SendWithProxy.resolve_proxy_target("http://127.0.0.1").should be_nil
      SendWithProxy.resolve_proxy_target("https://burp.local").should be_nil
    end

    it "refuses a schemeless host:port, where URI#host is nil" do
      SendWithProxy.resolve_proxy_target("127.0.0.1:8080").should be_nil
      # `localhost:8080` parses as scheme=localhost, opaque=8080.
      SendWithProxy.resolve_proxy_target("localhost:8080").should be_nil
    end

    it "refuses an out-of-range port" do
      SendWithProxy.resolve_proxy_target("http://127.0.0.1:99999").should be_nil
    end

    it "refuses an empty value" do
      SendWithProxy.resolve_proxy_target("").should be_nil
    end
  end

  describe "unusable --probe-via" do
    it "sends nothing when the proxy URL has no port" do
      target = StubProxy.new
      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(".")])
        # URI#port is nil here, so Crest used to drop the proxy entirely.
        options["probe_via"] = YAML::Any.new("http://127.0.0.1")

        SendWithProxy.new(options).run([Endpoint.new("#{target.url}/api/ping", "GET")])

        target.requests.size.should eq(0)
      ensure
        target.close
      end
    end

    it "sends nothing when the proxy URL has no scheme (URI#host is nil)" do
      target = StubProxy.new
      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(".")])
        # `curl -x` accepts this shape; URI.parse yields host=nil. The CLI
        # normalizes it to http:// before we get here, but config-file and
        # library callers skip that path, so the deliverer must refuse.
        options["probe_via"] = YAML::Any.new("127.0.0.1:#{target.address.port}")

        SendWithProxy.new(options).run([Endpoint.new("#{target.url}/api/ping", "GET")])

        target.requests.size.should eq(0)
      ensure
        target.close
      end
    end
  end
end
