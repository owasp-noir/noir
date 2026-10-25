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
  # `home` unwraps the Address of Profile's own package, not the one the
  # resource imports.
  Endpoint.new("/v1/session/profile", "PUT", [
    Param.new("name", "", "json"),
    Param.new("home_city", "", "json"),
    Param.new("home_zip", "", "json"),
  ]),
  Endpoint.new("/v1/session/planet", "PUT", [Param.new("planet", "", "json")]),
  # A self-unwrapping field contributes nothing.
  Endpoint.new("/v1/session/node", "POST", [Param.new("id", "", "json")]),
  Endpoint.new("/v1/guava/required", "GET", [Param.new("Content-MD5", "", "header")]),
  Endpoint.new("/v1/guava/optional", "GET"),
  # The implementing method's `@Auth` is injection too.
  Endpoint.new("/v1/account/me", "GET"),
  Endpoint.new("/v1/custom", "GET"),
  Endpoint.new("/v1/audit", "GET"),
]

tester = FunctionalTester.new("fixtures/java/dropwizard_auth/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Dropwizard @Auth principal", tags: "functional" do
  it "guards only Dropwizard's @Auth on a parameter that is not java.util.Optional" do
    taggers = ->(method : String, url : String) do
      tester.app.endpoints.find! { |ep| ep.method == method && ep.url == url }.tags.select(&.name.==("auth")).map(&.tagger)
    end

    taggers.call("GET", "/v1/session/{id}").should eq ["dropwizard_auth"]
    taggers.call("POST", "/v1/session").should be_empty # @Auth java.util.Optional<User>
    taggers.call("PUT", "/v1/session/profile").should be_empty
    # Guava's Optional is a required principal; a qualified java.util.Optional is not.
    taggers.call("GET", "/v1/guava/required").should eq ["dropwizard_auth"]
    taggers.call("GET", "/v1/guava/optional").should be_empty
    # @Auth on the implementing method of an interface-declared route.
    taggers.call("GET", "/v1/account/me").should eq ["dropwizard_auth"]
    # An `Auth` that resolves elsewhere: a single-type import beating
    # `io.dropwizard.auth.*`, and a same-package type (whose file comment
    # mentions `@io.dropwizard.auth.Auth`).
    taggers.call("GET", "/v1/custom").should be_empty
    taggers.call("GET", "/v1/audit").should be_empty
  end
end
