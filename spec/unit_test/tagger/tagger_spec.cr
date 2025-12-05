require "../../spec_helper"
require "../../../src/tagger/tagger"

describe "Tagger" do
  it "hunt_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("q", "", "query"),
        Param.new("query", "", "query"),
        Param.new("filter", "", "query"),
        Param.new("X-Forwarded-For", "", "header"),
      ]),
      Endpoint.new("/api/sign_ups", "POST", [
        Param.new("url", "", "cookie"),
        Param.new("command", "", "cookie"),
        Param.new("role", "", "cookie"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "hunt")
    expected_endpoints.each do |endpoint|
      endpoint.params.each do |param|
        case param.name
        when "query"
          param.tags.empty?.should be_false
          param.tags.each do |tag|
            tag.name.should eq("sqli")
          end
        when "url"
          param.tags.empty?.should be_false
          param.tags.each do |tag|
            tag.name.should eq("ssrf")
          end
        when "role"
          param.tags.empty?.should be_false
          param.tags.each do |tag|
            tag.name.should eq("sqli")
          end
        end
      end
    end
  end

  it "oauth_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/token", "GET", [
        Param.new("client_id", "", "query"),
        Param.new("grant_type", "", "query"),
        Param.new("code", "", "query"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "oauth")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("oauth")
      end
    end
  end

  it "cors_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("q", "", "query"),
        Param.new("Origin", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "cors")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("cors")
      end
    end
  end

  it "soap_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("SOAPAction", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "soap")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("soap")
      end
    end
  end

  it "websocket_tagger_1" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/ws", "GET", [
        Param.new("sec-websocket-version", "", "header"),
        Param.new("Sec-WebSocket-Key", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "websocket")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end

  it "websocket_tagger_2" do
    noir_options = create_test_options
    e = Endpoint.new("/ws", "GET")
    e.protocol = "ws"

    expected_endpoints = [e]

    NoirTaggers.run_tagger(expected_endpoints, noir_options, "websocket")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end

  it "graphql_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/graphql", "POST", [
        Param.new("query", "{ users { id } }", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "graphql")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("graphql")
      end
    end
  end

  it "jwt_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/auth/token", "POST", [
        Param.new("token", "", "form"),
        Param.new("refresh_token", "", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "jwt")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("jwt")
      end
    end
  end

  it "file_upload_tagger" do
    noir_options = create_test_options
    expected_endpoints = [
      Endpoint.new("/api/upload", "POST", [
        Param.new("file", "", "form"),
      ]),
    ]
    NoirTaggers.run_tagger(expected_endpoints, noir_options, "file_upload")
    expected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("file_upload")
      end
    end
  end
end
