require "../../spec_helper"
require "http/server"
require "json"
require "yaml"
require "../../../src/deliver/send_webhook"
require "../../../src/models/endpoint"

# Same capturing-server pattern the ES spec uses; scoped to the single
# POST that SendWebhook issues.
private class WebhookCapturingServer
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
      context.response.print %({"ok":true})
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

describe SendWebhook do
  it "POSTs a JSON body with endpoints + endpoint_count + noir_version" do
    server = WebhookCapturingServer.new
    begin
      sender = SendWebhook.new(base_deliver_options)
      sender.run([
        Endpoint.new("/api/users", "GET"),
        Endpoint.new("/api/login", "POST"),
      ], "#{server.url}/hook")

      server.requests.size.should eq(1)
      req = server.requests.first
      req[:method].should eq("POST")
      req[:path].should eq("/hook")
      req[:headers]["Content-Type"]?.should eq("application/json")

      parsed = JSON.parse(req[:body])
      parsed["endpoints"].as_a.size.should eq(2)
      parsed["endpoint_count"].as_i.should eq(2)
      parsed["noir_version"].as_s.should_not be_empty
      parsed["endpoints"][0]["url"].as_s.should eq("/api/users")
    ensure
      server.close
    end
  end

  it "merges --probe-header (send_with_headers) into the POST" do
    server = WebhookCapturingServer.new
    begin
      options = base_deliver_options
      options["probe_header"] = YAML::Any.new([
        YAML::Any.new("X-Auth: tok123"),
      ])
      sender = SendWebhook.new(options)
      sender.run([Endpoint.new("/x", "GET")], server.url)

      req = server.requests.first
      req[:headers]["X-Auth"]?.should eq("tok123")
    ensure
      server.close
    end
  end

  it "does not leak Content-Type/Accept back into @headers across calls" do
    server = WebhookCapturingServer.new
    begin
      options = base_deliver_options
      options["probe_header"] = YAML::Any.new([
        YAML::Any.new("X-Trace-Id: t1"),
      ])
      sender = SendWebhook.new(options)
      sender.run([Endpoint.new("/x", "GET")], server.url)

      sender.headers.has_key?("Content-Type").should be_false
      sender.headers.has_key?("Accept").should be_false
      sender.headers["X-Trace-Id"]?.should eq("t1")
    ensure
      server.close
    end
  end

  it "swallows network errors instead of bubbling out of run" do
    sender = SendWebhook.new(base_deliver_options)
    # Unreachable port → Crest raises; the rescue inside `run` absorbs
    # it so a misconfigured --export-webhook URL doesn't crash noir.
    sender.run([Endpoint.new("/x", "GET")], "http://127.0.0.1:1/dead").should be_nil
  end
end
