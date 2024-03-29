require "../../../src/tagger/tagger"

describe "Tagger" do
  it "hunt_tagger" do
    noir_options = default_options()
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
          param.tags.each do |tag|
            tag.name.should eq("sqli")
          end
        when "url"
          param.tags.each do |tag|
            tag.name.should eq("ssrf")
          end
        when "role"
          param.tags.each do |tag|
            tag.name.should eq("sqli")
          end
        end
      end
    end
  end

  it "oauth_tagger" do
    noir_options = default_options()
    extected_endpoints = [
      Endpoint.new("/token", "GET", [
        Param.new("client_id", "", "query"),
        Param.new("grant_type", "", "query"),
        Param.new("code", "", "query"),
      ]),
    ]
    NoirTaggers.run_tagger(extected_endpoints, noir_options, "oauth")
    extected_endpoints.each do |endpoint|
      endpoint.tags.each do |tag|
        tag.name.should eq("oauth")
      end
    end
  end
end
