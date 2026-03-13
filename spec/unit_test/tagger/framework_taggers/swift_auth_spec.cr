require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "SwiftAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/swift/vapor_auth"
  routes_path = "#{fixture_base}/Sources/routes.swift"

  # routes.swift line reference:
  #  4: app.get("public") { req in
  #  8: let protected = app.grouped(UserAuthenticator())
  #  9: protected.get("profile") { req in
  # 10:     let user = try req.auth.require(User.self)
  # 14: protected.post("api", "data") { req in
  # 18: app.get("health") { req in

  it "detects .grouped(UserAuthenticator()) middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(routes_path, 9))
    details.technology = "swift_vapor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = SwiftAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("swift_auth")
    endpoint.tags[0].description.should contain("Vapor")
  end

  it "detects req.auth.require in handler body" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(routes_path, 9))
    details.technology = "swift_vapor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = SwiftAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "does not tag public routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(routes_path, 4))
    details.technology = "swift_vapor"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = SwiftAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag health route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(routes_path, 18))
    details.technology = "swift_vapor"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = SwiftAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
