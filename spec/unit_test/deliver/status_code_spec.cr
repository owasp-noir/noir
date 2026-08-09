require "../../spec_helper"
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
end
