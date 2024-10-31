require "../../../src/tagger/tagger"

describe "Tagger" do
  it "hunt_tagger" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    extected_endpoints = [
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
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "hunt")
    extected_endpoints.each do |endpoint|
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
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    extected_endpoints = [
      Endpoint.new("/token", "GET", [
        Param.new("client_id", "", "query"),
        Param.new("grant_type", "", "query"),
        Param.new("code", "", "query"),
      ]),
    ]
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "oauth")
    extected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("oauth")
      end
    end
  end

  it "cors_tagger" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    extected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("q", "", "query"),
        Param.new("Origin", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "cors")
    extected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("cors")
      end
    end
  end

  it "soap_tagger" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    extected_endpoints = [
      Endpoint.new("/api/me", "GET", [
        Param.new("SOAPAction", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "soap")
    extected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("soap")
      end
    end
  end

  it "websocket_tagger_1" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    extected_endpoints = [
      Endpoint.new("/ws", "GET", [
        Param.new("sec-websocket-version", "", "header"),
        Param.new("Sec-WebSocket-Key", "", "header"),
      ]),
    ]
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "websocket")
    extected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end

  it "websocket_tagger_2" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    e = Endpoint.new("/ws", "GET")
    e.protocol = "ws"

    extected_endpoints = [e]

    NoirTaggers.run_tagger(extected_endpoints, noir_options, "websocket")
    extected_endpoints.each do |endpoint|
      endpoint.tags.empty?.should be_false
      endpoint.tags.each do |tag|
        tag.name.should eq("websocket")
      end
    end
  end
end
