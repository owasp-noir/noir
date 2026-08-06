require "../../spec_helper"
require "http/server"
require "yaml"
require "../../../src/deliver/send_req"
require "../../../src/models/endpoint"

# In-process HTTP server bound to an ephemeral port. The spec drives
# SendReq against it and inspects the requests the handler captured.
#
# Crystal's HTTP::Server is non-async in this configuration, but we
# spawn the `listen` call into a fiber so the calling spec can fire
# requests against it from the main fiber.
private class CapturingServer
  getter requests : Array(NamedTuple(method: String, path: String, headers: HTTP::Headers, body: String))
  getter address : Socket::IPAddress

  def initialize(@status : Int32 = 200)
    @requests = [] of NamedTuple(method: String, path: String, headers: HTTP::Headers, body: String)
    status = @status
    @server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      # Dup headers so the spec sees a stable snapshot, not the live
      # connection's header object.
      hdrs = HTTP::Headers.new
      context.request.headers.each { |k, v| v.each { |vv| hdrs.add(k, vv) } }
      # Crest emits the absolute form in the request line (`GET
      # http://host:port/path HTTP/1.1`) so normalize to just the path
      # component for assertions — that's what callers actually care
      # about.
      resource = context.request.resource
      path = if resource.starts_with?("http://") || resource.starts_with?("https://")
               URI.parse(resource).request_target
             else
               resource
             end
      @requests << {
        method:  context.request.method,
        path:    path,
        headers: hdrs,
        body:    body,
      }
      context.response.status_code = status
      context.response.print "ok"
    end
    @address = @server.bind_tcp("127.0.0.1", 0)
    spawn { @server.listen }
    # Yield once so the listen fiber is actually accepting before the
    # spec starts sending. Without this the first request can race the
    # bind and connect-refuse intermittently on cold runs.
    Fiber.yield
  end

  def url_for(path : String) : String
    "http://#{@address.address}:#{@address.port}#{path}"
  end

  def close
    @server.close
  end
end

# A server that accepts the connection and then never answers — a wedged or
# blackholed host.
#
# The handler blocks on a channel rather than sleeping a fixed span. A bare
# `sleep` keeps running after `close`, so the handler would wake up inside
# whatever spec file happened to be executing by then and write to a
# torn-down server. Closing the channel releases the fiber immediately, and
# the stall is unbounded while the spec runs, which is a truer blackhole.
private class StallingServer
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

# Real timeouts are 5s/15s; overriding keeps the spec fast while still
# exercising the same plumbing into Crest.
private class ImpatientSendReq < SendReq
  protected def probe_read_timeout : Time::Span
    150.milliseconds
  end
end

private def base_deliver_options
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(".")])
  options
end

describe SendReq do
  it "sends a GET request when the endpoint has no params" do
    server = CapturingServer.new
    begin
      ep = Endpoint.new(server.url_for("/health"), "GET")

      options = base_deliver_options
      sender = SendReq.new(options)
      sender.run([ep])

      server.requests.size.should eq(1)
      req = server.requests.first
      req[:method].should eq("GET")
      req[:path].should eq("/health")
      req[:headers]["User-Agent"]?.should match(/^Noir\//)
    ensure
      server.close
    end
  end

  it "sends a POST with form body when the endpoint has form params" do
    server = CapturingServer.new
    begin
      ep = Endpoint.new(server.url_for("/login"), "POST")
      ep.params << Param.new("username", "alice", "form")
      ep.params << Param.new("password", "s3cret", "form")

      sender = SendReq.new(base_deliver_options)
      sender.run([ep])

      server.requests.size.should eq(1)
      req = server.requests.first
      req[:method].should eq("POST")
      req[:headers]["Content-Type"]?.should_not be_nil
      req[:headers]["Content-Type"].should contain("application/x-www-form-urlencoded")
      req[:body].should contain("username=alice")
      req[:body].should contain("password=s3cret")
    ensure
      server.close
    end
  end

  it "sends a POST with JSON body when the endpoint has json params" do
    server = CapturingServer.new
    begin
      ep = Endpoint.new(server.url_for("/api/users"), "POST")
      ep.params << Param.new("name", "bob", "json")

      sender = SendReq.new(base_deliver_options)
      sender.run([ep])

      server.requests.size.should eq(1)
      req = server.requests.first
      req[:headers]["Content-Type"]?.should_not be_nil
      req[:headers]["Content-Type"].should contain("application/json")
      req[:body].should contain("\"name\"")
      req[:body].should contain("\"bob\"")
    ensure
      server.close
    end
  end

  it "attaches user-supplied --probe-header to every request" do
    server = CapturingServer.new
    begin
      ep = Endpoint.new(server.url_for("/ping"), "GET")

      options = base_deliver_options
      options["probe_header"] = YAML::Any.new([
        YAML::Any.new("X-Api-Key: abc123"),
        YAML::Any.new("Authorization: Bearer x:y:z"),
      ])
      sender = SendReq.new(options)
      sender.run([ep])

      req = server.requests.first
      req[:headers]["X-Api-Key"]?.should eq("abc123")
      # Multi-colon values must keep their full payload (Deliver only
      # splits on the first ':').
      req[:headers]["Authorization"]?.should eq("Bearer x:y:z")
    ensure
      server.close
    end
  end

  it "expands synthetic ANY endpoints before sending requests" do
    server = CapturingServer.new
    begin
      ep = Endpoint.new(server.url_for("/wildcard"), "ANY")

      sender = SendReq.new(base_deliver_options)
      sender.run([ep])

      methods = server.requests.map(&.[:method]).sort!
      methods.should eq(WILDCARD_HTTP_METHODS.sort)
      methods.includes?("ANY").should be_false
    ensure
      server.close
    end
  end

  it "applies matchers before sending and skips non-matching endpoints" do
    server = CapturingServer.new
    begin
      ep_keep = Endpoint.new(server.url_for("/admin/users"), "GET")
      ep_drop = Endpoint.new(server.url_for("/public/info"), "GET")

      options = base_deliver_options
      options["probe_match"] = YAML::Any.new([YAML::Any.new("/admin")])
      sender = SendReq.new(options)
      sender.run([ep_keep, ep_drop])

      paths = server.requests.map(&.[:path])
      paths.should eq(["/admin/users"])
    ensure
      server.close
    end
  end

  it "matches an absolute-URL pattern instead of reading its scheme as a method" do
    server = CapturingServer.new
    begin
      ep_keep = Endpoint.new(server.url_for("/public/info"), "GET")
      ep_drop = Endpoint.new(server.url_for("/admin/users"), "GET")

      options = base_deliver_options
      # Every delivery target requires -u, so endpoint URLs are absolute and
      # pasting one into --probe-skip is the natural thing to do. Splitting
      # on the first ':' used to read this as method `HTTP` + url
      # `//127.0.0.1:PORT/admin`, matching nothing at all.
      options["probe_skip"] = YAML::Any.new([YAML::Any.new(server.url_for("/admin"))])
      sender = SendReq.new(options)
      sender.run([ep_keep, ep_drop])

      paths = server.requests.map(&.[:path])
      paths.should eq(["/public/info"])
    ensure
      server.close
    end
  end

  it "still honours the METHOD:url pattern form" do
    server = CapturingServer.new
    begin
      ep_get = Endpoint.new(server.url_for("/admin/users"), "GET")
      ep_post = Endpoint.new(server.url_for("/admin/users"), "POST")

      options = base_deliver_options
      options["probe_match"] = YAML::Any.new([YAML::Any.new("POST:/admin")])
      sender = SendReq.new(options)
      sender.run([ep_get, ep_post])

      server.requests.map(&.[:method]).should eq(["POST"])
    ensure
      server.close
    end
  end

  # Crest raises on any non-2xx unless `handle_errors: false`, which fed
  # the failure counter and — because `/users/{id}` templates are probed
  # literally — made "N request(s) failed" fire on nearly every real scan,
  # burying the genuinely-broken-target case it exists for.
  it "treats an HTTP error response as a delivered probe, not a failure" do
    [404, 500].each do |status|
      server = CapturingServer.new(status)
      begin
        sender = SendReq.new(base_deliver_options)
        sender.run([Endpoint.new(server.url_for("/gone"), "GET")])

        server.requests.size.should eq(1)
        server.requests.first[:path].should eq("/gone")
        # Pre-fix Crest raised Crest::RequestFailed here, landing in the
        # rescue and bumping the counter that drives the warning.
        sender.undeliverable_count.should eq(0)
      ensure
        server.close
      end
    end
  end

  it "still counts a request that never reached the host" do
    # Nothing listening — a real delivery failure, which must keep
    # surfacing now that HTTP error responses no longer do.
    sender = SendReq.new(base_deliver_options)
    sender.run([Endpoint.new("http://127.0.0.1:1/dead", "GET")])

    sender.undeliverable_count.should eq(1)
  end

  # `max_redirects: 0` has to travel with `handle_errors: false`: Crest's
  # `check_max_redirects` raises when `max_redirects <= 0 && handle_errors`,
  # so setting it alone turns every 3xx into a counted failure.
  it "does not follow redirects, so --probe-header credentials stay on the target host" do
    final = CapturingServer.new
    begin
      redirect_target = final.url_for("/elsewhere")
      redirector = HTTP::Server.new do |ctx|
        ctx.response.status_code = 302
        ctx.response.headers["Location"] = redirect_target
      end
      addr = redirector.bind_tcp("127.0.0.1", 0)
      spawn { redirector.listen }
      Fiber.yield

      begin
        options = base_deliver_options
        options["probe_header"] = YAML::Any.new([
          YAML::Any.new("Authorization: Bearer probe-secret"),
        ])
        SendReq.new(options).run([Endpoint.new("http://#{addr.address}:#{addr.port}/start", "GET")])

        # Crest copies request headers onto the redirected request and
        # follows absolute Locations to other hosts, so pre-fix the token
        # landed here.
        final.requests.size.should eq(0)
      ensure
        redirector.close
      end
    ensure
      final.close
    end
  end

  # Crest defaults read_timeout to nil, so a host that accepted the
  # connection and then went quiet held its --concurrency slot forever and
  # `run` never returned. Enough such hosts starved every other endpoint.
  it "gives up on a stalled host instead of blocking forever" do
    server = StallingServer.new
    begin
      finished = Channel(Nil).new(1)
      spawn do
        ImpatientSendReq.new(base_deliver_options).run([Endpoint.new(server.url_for("/hang"), "GET")])
        finished.send(nil)
      end

      returned = false
      select
      when finished.receive
        returned = true
      when timeout(4.seconds)
        returned = false
      end

      # Pre-fix this waited out the full 10s stall; with no timeout at all a
      # genuinely wedged host waited forever.
      returned.should be_true
    ensure
      server.close
    end
  end

  it "counts a timed-out probe as undeliverable" do
    server = StallingServer.new
    begin
      sender = ImpatientSendReq.new(base_deliver_options)
      sender.run([Endpoint.new(server.url_for("/hang"), "GET")])

      sender.undeliverable_count.should eq(1)
    ensure
      server.close
    end
  end

  # The optimizer only substitutes a path placeholder when --set-pvalue-path
  # supplied a value, so a default scan probes `/users/{id}` literally and
  # 404s. Filling it is restricted to read-only verbs: `DELETE /users/{id}` is
  # a harmless 404 today and must not silently become a real delete.
  describe "path template filling" do
    it "fills the template for a GET so the probe reaches the route" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/users/{id}"), "GET")
        ep.params << Param.new("id", "", "path")

        SendReq.new(base_deliver_options).run([ep])

        server.requests.first[:path].should eq("/users/1")
      ensure
        server.close
      end
    end

    it "uses a string for a non-numeric param name" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/files/{key}"), "GET")
        ep.params << Param.new("key", "", "path")

        SendReq.new(base_deliver_options).run([ep])

        server.requests.first[:path].should eq("/files/noir")
      ensure
        server.close
      end
    end

    it "fills Express-style :name and Django-style <name> too" do
      server = CapturingServer.new
      begin
        express = Endpoint.new(server.url_for("/posts/:post_id"), "GET")
        express.params << Param.new("post_id", "", "path")
        django = Endpoint.new(server.url_for("/tags/<slug>"), "GET")
        django.params << Param.new("slug", "", "path")

        SendReq.new(base_deliver_options).run([express, django])

        server.requests.map(&.[:path]).sort!.should eq(["/posts/1", "/tags/noir"])
      ensure
        server.close
      end
    end

    it "leaves the template alone for destructive verbs" do
      server = CapturingServer.new
      begin
        %w[DELETE POST PUT PATCH].each do |verb|
          ep = Endpoint.new(server.url_for("/users/{id}"), verb)
          ep.params << Param.new("id", "", "path")
          SendReq.new(base_deliver_options).run([ep])
        end

        # Every one keeps the literal template — nothing resolves to /users/1.
        server.requests.map(&.[:path]).uniq!.should eq(["/users/{id}"])
        server.requests.map(&.[:method]).sort!.should eq(%w[DELETE PATCH POST PUT])
      ensure
        server.close
      end
    end

    it "does not touch a param --set-pvalue-path already resolved" do
      server = CapturingServer.new
      begin
        # The optimizer substitutes into the URL and records the value, so
        # there is no placeholder left and the recorded value must win.
        ep = Endpoint.new(server.url_for("/users/42"), "GET")
        ep.params << Param.new("id", "42", "path")

        SendReq.new(base_deliver_options).run([ep])

        server.requests.first[:path].should eq("/users/42")
      ensure
        server.close
      end
    end

    it "does not mangle the port in an absolute URL" do
      server = CapturingServer.new
      begin
        # `:id` is only filled at a segment boundary, so `host:PORT` and
        # embedded text like `celeb_:USERNAME` are left intact.
        ep = Endpoint.new(server.url_for("/profiles/celeb_:USERNAME"), "GET")
        ep.params << Param.new("USERNAME", "", "path")

        SendReq.new(base_deliver_options).run([ep])

        server.requests.size.should eq(1)
        server.requests.first[:path].should contain("celeb_:USERNAME")
      ensure
        server.close
      end
    end

    it "leaves endpoint.url itself unchanged so the report keeps the template" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/users/{id}"), "GET")
        ep.params << Param.new("id", "", "path")

        SendReq.new(base_deliver_options).run([ep])

        ep.url.should eq(server.url_for("/users/{id}"))
      ensure
        server.close
      end
    end
  end

  # Probes read only the query/json/form buckets, so an endpoint whose auth is
  # a discovered header param was probed without it and came back 401 with no
  # visible cause.
  describe "discovered header / cookie params" do
    it "sends header params as request headers" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/api/items"), "GET")
        ep.params << Param.new("X-API-Key", "discovered-key", "header")

        SendReq.new(base_deliver_options).run([ep])

        server.requests.first[:headers]["X-API-Key"]?.should eq("discovered-key")
      ensure
        server.close
      end
    end

    it "folds cookie params into a single Cookie header" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/dashboard"), "GET")
        ep.params << Param.new("session", "abc", "cookie")
        ep.params << Param.new("csrf", "xyz", "cookie")

        SendReq.new(base_deliver_options).run([ep])

        cookie = server.requests.first[:headers]["Cookie"]?
        cookie.should_not be_nil
        cookie.not_nil!.should contain("session=abc")
        cookie.not_nil!.should contain("csrf=xyz")
      ensure
        server.close
      end
    end

    it "lets an explicit --probe-header win over a discovered param" do
      server = CapturingServer.new
      begin
        ep = Endpoint.new(server.url_for("/api/items"), "GET")
        ep.params << Param.new("X-API-Key", "discovered-key", "header")

        options = base_deliver_options
        options["probe_header"] = YAML::Any.new([YAML::Any.new("X-API-Key: user-key")])
        SendReq.new(options).run([ep])

        server.requests.first[:headers]["X-API-Key"]?.should eq("user-key")
      ensure
        server.close
      end
    end

    it "does not leak one endpoint's discovered headers onto another's request" do
      server = CapturingServer.new
      begin
        with_header = Endpoint.new(server.url_for("/secured"), "GET")
        with_header.params << Param.new("X-Tenant", "acme", "header")
        without = Endpoint.new(server.url_for("/public"), "GET")

        # `@headers` is shared across every probe fiber, so building the
        # per-request set by mutating it in place would bleed across endpoints.
        SendReq.new(base_deliver_options).run([with_header, without])

        by_path = server.requests.to_h { |r| {r[:path], r[:headers]} }
        by_path["/secured"]["X-Tenant"]?.should eq("acme")
        by_path["/public"]["X-Tenant"]?.should be_nil
      ensure
        server.close
      end
    end
  end

  # `internal` marks Spring @FeignClient / @HttpExchange declarations: calls
  # the app makes to other services, not routes it serves. Firing them at the
  # -u target hits a host that doesn't own those paths.
  it "does not probe endpoints marked internal" do
    server = CapturingServer.new
    begin
      own_route = Endpoint.new(server.url_for("/api/orders"), "GET")
      feign_client = Endpoint.new(server.url_for("/billing/charge"), "POST")
      feign_client.internal = true

      SendReq.new(base_deliver_options).run([own_route, feign_client])

      server.requests.map(&.[:path]).should eq(["/api/orders"])
    ensure
      server.close
    end
  end

  it "swallows network errors so one bad endpoint doesn't abort the batch" do
    server = CapturingServer.new
    begin
      good_ep = Endpoint.new(server.url_for("/ok"), "GET")
      # Unreachable port — Crest will raise, and the rescue in SendReq
      # must keep the WaitGroup intact so the spec doesn't hang and the
      # other endpoint still reaches the server.
      bad_ep = Endpoint.new("http://127.0.0.1:1/dead", "GET")

      sender = SendReq.new(base_deliver_options)
      sender.run([good_ep, bad_ep])

      paths = server.requests.map(&.[:path])
      paths.should contain("/ok")
    ensure
      server.close
    end
  end
end
