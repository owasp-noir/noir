require "../../func_spec.cr"

expected_endpoints = [
  # `@Auth User` is injection, not a body; `HttpHeaders.USER_AGENT` is the
  # header's wire name.
  Endpoint.new("/v1/session/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("User-Agent", "", "header"),
  ]),
  # `@JsonUnwrapped SessionUpdate update` contributes its properties, not `update`.
  Endpoint.new("/v1/session", "POST", [
    Param.new("number", "", "json"),
    Param.new("push_token", "", "json"),
    Param.new("captcha", "", "json"),
  ]),
  Endpoint.new("/v1/session/profile", "PUT", [
    Param.new("name", "", "json"),
    Param.new("home_city", "", "json"),
    Param.new("home_zip", "", "json"),
  ]),
]

tester = FunctionalTester.new("fixtures/java/dropwizard_auth/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Dropwizard @Auth principal", tags: "functional" do
  it "guards only a required (non-Optional) @Auth parameter" do
    auth = ->(method : String, url : String) do
      tester.app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.select(&.name.==("auth"))
    end

    auth.call("GET", "/v1/session/{id}").map(&.tagger).should eq ["dropwizard_auth"]
    auth.call("POST", "/v1/session").should be_empty
    auth.call("PUT", "/v1/session/profile").should be_empty
  end
end
