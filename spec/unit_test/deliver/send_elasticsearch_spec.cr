require "../../spec_helper"
require "http/server"
require "json"
require "yaml"
require "../../../src/deliver/send_elasticsearch"
require "../../../src/models/endpoint"

# Pared-down version of the send_req spec's capturing server, scoped
# to the single POST that send_elasticsearch issues.
private class EsCapturingServer
  getter requests : Array(NamedTuple(method: String, path: String, headers: HTTP::Headers, body: String))
  getter address : Socket::IPAddress

  def initialize
    @requests = [] of NamedTuple(method: String, path: String, headers: HTTP::Headers, body: String)
    @server = HTTP::Server.new do |context|
      body = context.request.body.try(&.gets_to_end) || ""
      hdrs = HTTP::Headers.new
      context.request.headers.each { |k, v| v.each { |vv| hdrs.add(k, vv) } }
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
      context.response.content_type = "application/json"
      context.response.print %({"result":"created"})
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

private def base_deliver_options
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(".")])
  options
end

describe SendElasticSearch do
  it "POSTs the endpoint payload as JSON with ES content-type/accept headers" do
    server = EsCapturingServer.new
    begin
      ep = Endpoint.new("/api/users", "GET")
      sender = SendElasticSearch.new(base_deliver_options)
      sender.run([ep], "#{server.url}/noir/_doc")

      server.requests.size.should eq(1)
      req = server.requests.first
      req[:method].should eq("POST")
      req[:path].should eq("/noir/_doc")
      req[:headers]["Content-Type"]?.should eq("application/json")
      req[:headers]["Accept"]?.should eq("application/json")
      # Payload wraps endpoints under the `endpoints` key.
      parsed = JSON.parse(req[:body])
      parsed["endpoints"].as_a.size.should eq(1)
      parsed["endpoints"][0]["url"].as_s.should eq("/api/users")
    ensure
      server.close
    end
  end

  it "does not leak ES-only headers (Content-Type/Accept) back into @headers" do
    server = EsCapturingServer.new
    begin
      ep = Endpoint.new("/x", "GET")

      options = base_deliver_options
      options["probe_header"] = YAML::Any.new([
        YAML::Any.new("X-Trace-Id: t1"),
      ])
      sender = SendElasticSearch.new(options)
      sender.run([ep], server.url)

      # After the first send, @headers must still be just the
      # user-supplied set. The previous shape aliased es_headers to
      # @headers and mutated both — this regression test pins the
      # post-fix behaviour.
      sender.headers.has_key?("Content-Type").should be_false
      sender.headers.has_key?("Accept").should be_false
      sender.headers["X-Trace-Id"]?.should eq("t1")
    ensure
      server.close
    end
  end

  it "swallows network errors instead of bubbling out of run" do
    sender = SendElasticSearch.new(base_deliver_options)
    # Unreachable port → Crest raises; the rescue inside `run` must
    # absorb it so a misconfigured --export-es URL doesn't crash noir.
    # The assertion is just "no exception escapes" — `run` returns
    # nil after the rescue.
    sender.run([Endpoint.new("/x", "GET")], "http://127.0.0.1:1/dead").should be_nil
  end
end
