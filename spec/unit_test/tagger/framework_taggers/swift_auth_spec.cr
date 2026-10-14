require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "SwiftAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/swift/vapor_auth", __DIR__)
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

  it "does not read the next route's body after a one-line closure" do
    tmpdir = File.tempname("swift_oneline")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "routes.swift")
    File.write(routes, [
      "func routes(_ app: Application) throws {",
      "    app.get(\"hello\") { req in \"Hello\" }",
      "    app.get(\"me\") { req -> String in",
      "        let user = try req.auth.require(User.self)",
      "        return user.name",
      "    }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    hello = Endpoint.new("/hello", "GET", [] of Param, Details.new(PathInfo.new(routes, 2)))
    me = Endpoint.new("/me", "GET", [] of Param, Details.new(PathInfo.new(routes, 3)))
    SwiftAuthTagger.new(noir_options).perform([hello, me])

    hello.tags.should be_empty
    me.tags.map(&.description).should eq(["Protected by Vapor req.auth.require"])

    FileUtils.rm_rf(tmpdir)
  end
end
