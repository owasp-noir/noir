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

  def initialize
    @requests = [] of NamedTuple(method: String, path: String, headers: HTTP::Headers, body: String)
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
      context.response.status_code = 200
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
