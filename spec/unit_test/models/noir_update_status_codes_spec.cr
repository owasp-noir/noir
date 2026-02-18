require "../../spec_helper"
require "../../../src/models/noir.cr"
require "../../../src/models/endpoint.cr"
require "../../../src/utils/http_symbols.cr"

# Mock Response object
class MockResponse
  property status_code : Int32

  def initialize(@status_code)
  end
end

# Test Runner that mocks external requests
class TestNoirRunner < NoirRunner
  property last_request_params : Hash(String, String)?
  property last_request_body : Hash(String, String)?
  property last_request_json : Bool?

  def perform_request(method, url, params = {} of String => String, form = {} of String => String, json = false)
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

describe "NoirRunner#update_status_codes" do
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new("noir")])
  options["exclude_codes"] = YAML::Any.new("404")

  it "updates status codes correctly" do
    runner = TestNoirRunner.new(options)
    runner.endpoints << Endpoint.new("http://example.com/200", "GET")
    runner.endpoints << Endpoint.new("http://example.com/500", "GET")

    runner.update_status_codes

    runner.endpoints.size.should eq(2)
    runner.endpoints[0].details.status_code.should eq(200)
    runner.endpoints[1].details.status_code.should eq(500)
  end

  it "excludes endpoints with excluded status codes" do
    runner = TestNoirRunner.new(options)
    runner.endpoints << Endpoint.new("http://example.com/200", "GET")
    runner.endpoints << Endpoint.new("http://example.com/404", "GET")

    runner.update_status_codes

    runner.endpoints.size.should eq(1)
    runner.endpoints[0].url.should eq("http://example.com/200")
  end

  it "handles request failures gracefully" do
    runner = TestNoirRunner.new(options)
    runner.endpoints << Endpoint.new("http://example.com/error", "GET")

    # It should not raise exception, but catch it and log error (which is suppressed in test options)
    # The endpoint should be kept in the list
    runner.update_status_codes

    runner.endpoints.size.should eq(1)
    runner.endpoints[0].url.should eq("http://example.com/error")
  end

  it "passes parameters to perform_request" do
    runner = TestNoirRunner.new(options)
    endpoint = Endpoint.new("http://example.com/200", "POST")
    endpoint.params << Param.new("id", "1", "query")
    endpoint.params << Param.new("data", "value", "form")
    runner.endpoints << endpoint

    runner.update_status_codes

    runner.last_request_params.should_not be_nil
    if params = runner.last_request_params
      params["id"].should eq("1")
    end

    runner.last_request_body.should_not be_nil
    if body = runner.last_request_body
      body["data"].should eq("value")
    end

    runner.last_request_json.should be_false
  end

  it "passes JSON body to perform_request when JSON param exists" do
    runner = TestNoirRunner.new(options)
    endpoint = Endpoint.new("http://example.com/200", "POST")
    endpoint.params << Param.new("data", "value", "json")
    runner.endpoints << endpoint

    runner.update_status_codes

    runner.last_request_body.should_not be_nil
    if body = runner.last_request_body
      body["data"].should eq("value")
    end

    runner.last_request_json.should be_true
  end
end
