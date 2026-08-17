require "../../spec_helper"
require "http/server"
require "../../../src/deliver/status_code.cr"
require "../../../src/models/endpoint.cr"
require "../../../src/utils/http_symbols.cr"

# Mock Response object
class MockResponse
  property status_code : Int32

  def initialize(@status_code)
  end
end

# Probe that answers from a canned table instead of the network.
class TestStatusCodeProbe < StatusCodeProbe
  property last_request_method : Symbol?
  property last_request_params : Hash(String, String)?
  property last_request_body : Hash(String, String)?
  property last_request_json : Bool?

  def perform_request(method, url, params = {} of String => String, form = {} of String => String, json = false)
    @last_request_method = method
    @last_request_params = params
    @last_request_body = form
    @last_request_json = json

    case url
    when "http://example.com/200"
      MockResponse.new(200)
    when "http://example.com/404"
      MockResponse.new(404)
    when "http://example.com/500"
      MockResponse.new(500)
    when "http://example.com/error"
      raise "Connection refused"
    else
      MockResponse.new(200)
    end
  end
end

# In-process server on an ephemeral port that counts what it was actually
# asked for. A redirect chain needs two of these, and the whole point of the
# redirect assertions is *which* server got a request.
private class CountingServer
  getter address : Socket::IPAddress
  getter paths : Array(String)

  def initialize(@status : Int32 = 200, location : String? = nil)
    @paths = [] of String
    @mutex = Mutex.new
    status = @status
    mutex = @mutex
    paths = @paths
    @server = HTTP::Server.new do |ctx|
      resource = ctx.request.resource
      path = if resource.starts_with?("http://") || resource.starts_with?("https://")
               URI.parse(resource).request_target
             else
               resource
             end
      mutex.synchronize { paths << path }
      ctx.response.headers["Location"] = location if location
      ctx.response.status_code = status
      ctx.response.print "ok"
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    # Yield once so the listen fiber is accepting before the first request,
    # otherwise a cold run can connect-refuse intermittently.
    Fiber.yield
  end

  def count : Int32
    @mutex.synchronize { @paths.size }
  end

  def url_for(path : String) : String
    "http://#{@address.address}:#{@address.port}#{path}"
  end

  def close
    @server.close
  end
end

# Accepts the connection and then never answers, releasing only on close — a
# wedged or blackholed host. A bare `sleep` would keep running past `close`
# and wake inside whatever spec file was executing by then.
private class StallingStatusServer
  getter address : Socket::IPAddress

  def initialize
    @release = Channel(Nil).new
    release = @release
    @server = HTTP::Server.new do |ctx|
      release.receive?
      ctx.response.print "late"
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url_for(path : String) : String
    "http://#{@address.address}:#{@address.port}#{path}"
  end

  def close
    @server.close
    @release.close
  end
end

# Records the high-water mark of simultaneously in-flight requests, so the
# --concurrency bound is assertable rather than assumed.
private class ConcurrencyWatchingServer
  getter address : Socket::IPAddress
  getter peak : Int32

  def initialize
    @in_flight = 0
    @peak = 0
    @mutex = Mutex.new
    @server = HTTP::Server.new do |ctx|
      @mutex.synchronize do
        @in_flight += 1
        @peak = @in_flight if @in_flight > @peak
      end
      # Hold the request open briefly so overlapping probes really do overlap.
      sleep 20.milliseconds
      @mutex.synchronize { @in_flight -= 1 }
      ctx.response.print "ok"
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    Fiber.yield
  end

  def url_for(path : String) : String
    "http://#{@address.address}:#{@address.port}#{path}"
  end

  def close
    @server.close
  end
end

# The shipped read timeout is 5s; overriding keeps the stall spec fast while
# still exercising the real plumbing into Crest.
private class ImpatientStatusCodeProbe < StatusCodeProbe
  protected def read_timeout : Time::Span
    200.milliseconds
  end
end

private class ExposedStatusCodeProbe < StatusCodeProbe
  def exposed_connect_timeout : Time::Span
    connect_timeout
  end
end

private def base_probe_options : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options
end

private def probe_for(options : Hash(String, YAML::Any)) : StatusCodeProbe
  StatusCodeProbe.new(options, NoirLogger.new(false, false, false, true))
end

describe StatusCodeProbe do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["exclude_codes"] = YAML::Any.new("404")

  probe = -> { TestStatusCodeProbe.new(options, NoirLogger.new(false, false, false, true)) }

  it "updates status codes correctly" do
    endpoints = [
      Endpoint.new("http://example.com/200", "GET"),
      Endpoint.new("http://example.com/500", "GET"),
    ]

    result = probe.call.apply(endpoints)

    result.size.should eq(2)
    result[0].details.status_code.should eq(200)
    result[1].details.status_code.should eq(500)
  end

  it "excludes endpoints with excluded status codes" do
    endpoints = [
      Endpoint.new("http://example.com/200", "GET"),
      Endpoint.new("http://example.com/404", "GET"),
    ]

    result = probe.call.apply(endpoints)

    result.size.should eq(1)
    result[0].url.should eq("http://example.com/200")
  end

  it "handles request failures gracefully" do
    # It should not raise, but catch and log the error (suppressed in test
    # options) and keep the endpoint in the list.
    result = probe.call.apply([Endpoint.new("http://example.com/error", "GET")])

    result.size.should eq(1)
    result[0].url.should eq("http://example.com/error")
  end

  it "passes parameters to perform_request" do
    endpoint = Endpoint.new("http://example.com/200", "POST")
    endpoint.params << Param.new("id", "1", "query")
    endpoint.params << Param.new("data", "value", "form")

    runner = probe.call
    runner.apply([endpoint])

    params = runner.last_request_params.should_not be_nil
    params["id"].should eq("1")

    body = runner.last_request_body.should_not be_nil
    body["data"].should eq("value")

    runner.last_request_json.should be_false
  end

  it "passes JSON body to perform_request when JSON param exists" do
    endpoint = Endpoint.new("http://example.com/200", "POST")
    endpoint.params << Param.new("data", "value", "json")

    runner = probe.call
    runner.apply([endpoint])

    body = runner.last_request_body.should_not be_nil
    body["data"].should eq("value")

    runner.last_request_json.should be_true
  end

  it "uses GET as the representative status probe for synthetic ANY methods" do
    runner = probe.call
    runner.apply([Endpoint.new("http://example.com/200", "ANY")])

    runner.last_request_method.should eq(:get)
  end

  it "keeps non-HTTP endpoints without requesting them" do
    # Mobile deep links, CLI command surfaces and realtime ws:// event
    # surfaces can't be HTTP-requested at all — Crest raises "Unsupported
    # scheme" on each. They must pass through untouched, the way SendReq /
    # SendWithProxy already skip them.
    deep_link = Endpoint.new("myapp://accounts/profile", "GET")
    deep_link.protocol = "mobile-scheme"

    cli = Endpoint.new("cli://noir/scan", "CLI")
    cli.protocol = "cli"

    runner = probe.call
    result = runner.apply([deep_link, cli, Endpoint.new("ws://room:lobby/new_msg", "SEND")])

    result.size.should eq(3)
    runner.last_request_method.should be_nil
    result.each(&.details.status_code.should(be_nil))
  end

  # Everything below drives the real `perform_request` at a local server: the
  # bugs are in what noir hands Crest, so a canned-response probe cannot see
  # them.
  describe "against a real server" do
    it "reports the redirect's own code and does not follow it" do
      final = CountingServer.new(200)
      begin
        redirector = CountingServer.new(302, final.url_for("/final"))
        begin
          endpoint = Endpoint.new(redirector.url_for("/redirect"), "GET")
          result = probe_for(base_probe_options).apply([endpoint])

          # Crest's max_redirects defaults to 10 and `Redirector#follow` only
          # stops at `<= 0`, so pre-fix the probe silently walked to /final
          # and reported *its* 200 for /redirect.
          result.size.should eq(1)
          result.first.details.status_code.should eq(302)
          redirector.count.should eq(1)
          # A cross-host absolute Location let the scanned app aim noir's
          # probes at a third party. The target of a probe is what the user
          # asked for, not what the server says.
          final.count.should eq(0)
        ensure
          redirector.close
        end
      ensure
        final.close
      end
    end

    it "lets --exclude-codes filter a 3xx now that the 3xx is visible" do
      final = CountingServer.new(200)
      begin
        redirector = CountingServer.new(302, final.url_for("/final"))
        begin
          options = base_probe_options
          options["exclude_codes"] = YAML::Any.new("302")
          result = probe_for(options).apply([Endpoint.new(redirector.url_for("/redirect"), "GET")])

          # Pre-fix `excluded.includes?(response.status_code)` was handed the
          # 200 from the redirect target, so --exclude-codes 302 did nothing.
          result.should be_empty
        ensure
          redirector.close
        end
      ensure
        final.close
      end
    end

    it "keeps the catalog in input order while probing concurrently" do
      server = CountingServer.new(200)
      begin
        endpoints = (1..12).map { |i| Endpoint.new(server.url_for("/r#{i}"), "GET") }

        result = probe_for(base_probe_options).apply(endpoints)

        result.map(&.url).should eq(endpoints.map(&.url))
        result.each(&.details.status_code.should(eq(200)))
      ensure
        server.close
      end
    end

    # `apply` used to walk endpoints one at a time with no bound and no
    # connect timeout, so an unreachable host cost every endpoint its own
    # full timeout in series — hours before any report was written.
    it "probes stalled endpoints concurrently instead of one after another" do
      server = StallingStatusServer.new
      begin
        endpoints = (1..8).map { |i| Endpoint.new(server.url_for("/hang#{i}"), "GET") }

        options = base_probe_options
        options["concurrency"] = YAML::Any.new("8")
        started = Time.instant
        result = ImpatientStatusCodeProbe.new(options, NoirLogger.new(false, false, false, true)).apply(endpoints)
        elapsed = Time.instant - started

        # 8 endpoints x a 200ms read timeout is 1.6s sequentially; run eight
        # at a time it is one timeout plus change. The bound is deliberately
        # loose — the assertion is "not serialized", not a latency budget.
        elapsed.should be < 1.second
        # Every endpoint still comes back (a timeout is logged, not dropped).
        result.size.should eq(8)
      ensure
        server.close
      end
    end

    it "bounds in-flight probes by --concurrency" do
      server = ConcurrencyWatchingServer.new
      begin
        endpoints = (1..12).map { |i| Endpoint.new(server.url_for("/c#{i}"), "GET") }

        options = base_probe_options
        options["concurrency"] = YAML::Any.new("3")
        probe_for(options).apply(endpoints)

        server.peak.should be <= 3
      ensure
        server.close
      end
    end

    it "sends a connect timeout so a host that drops SYNs can't hold the scan" do
      # Crest defaults connect_timeout to nil — no timeout at all — which fell
      # back to the OS TCP timeout of roughly 75s per endpoint.
      ExposedStatusCodeProbe.new(base_probe_options, NoirLogger.new(false, false, false, true))
        .exposed_connect_timeout.should eq(Deliver::PROBE_CONNECT_TIMEOUT)
    end
  end
end
