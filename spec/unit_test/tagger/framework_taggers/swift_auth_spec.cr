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

  it "matches auth middleware in any .grouped() argument" do
    tmpdir = File.tempname("swift_grouped")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "routes.swift")
    File.write(routes, [
      "func routes(_ app: Application) throws {",
      "    let tokenProtected = app.grouped(UserToken.authenticator(), User.guardMiddleware())",
      "    tokenProtected.get(\"profile\") { req -> String in",
      "        return \"profile\"",
      "    }",
      "    let logged = app.grouped(RequestLogger(), CORSMiddleware())",
      "    logged.get(\"open\") { req in \"open\" }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    profile = Endpoint.new("/profile", "GET", [] of Param, Details.new(PathInfo.new(routes, 3)))
    open = Endpoint.new("/open", "GET", [] of Param, Details.new(PathInfo.new(routes, 7)))
    SwiftAuthTagger.new(noir_options).perform([profile, open])

    profile.tags.map(&.description).should eq(["Protected by Vapor User.guardMiddleware()"])
    open.tags.should be_empty

    FileUtils.rm_rf(tmpdir)
  end

  it "applies a guarded group closure to routes in groups nested inside it" do
    tmpdir = File.tempname("swift_nested_group")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "routes.swift")
    File.write(routes, <<-SWIFT)
      func routes(_ app: Application) throws {
          app.group(User.TokenAuthenticator(), User.guardMiddleware()) { protected in
              protected.group(ReportingMiddleware()) {
                  $0.get("api", "items", use: ItemController.list)
              }
              app.get("api", "status", use: StatusController.show)
          }
          app.group(LoggingMiddleware()) { logged in
              logged.get("api", "open", use: ItemController.open)
          }
      }
      SWIFT

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(line : Int32) { Endpoint.new("/x", "GET", [] of Param, Details.new(PathInfo.new(routes, line))) }
    items, status, open = at.call(4), at.call(6), at.call(9)
    SwiftAuthTagger.new(noir_options).perform([items, status, open])

    items.tags.map(&.description).should eq(["Protected by Vapor User.guardMiddleware()"])
    status.tags.should be_empty
    open.tags.should be_empty
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "reads the named handler method a route registers with use:" do
    tmpdir = File.tempname("swift_named_handler")
    Dir.mkdir_p(tmpdir)
    controller = File.join(tmpdir, "UserController.swift")
    File.write(controller, <<-SWIFT)
      struct UserController {
          func addRoutes(to group: RouterGroup<AppRequestContext>) {
              group.post(use: self.create)
              group.add(middleware: self.sessionAuthenticator)
                  .get(use: self.current)
          }

          func create(_ request: Request, context: AppRequestContext) async throws -> UserResponse {
              let user = try await request.decode(as: CreateUser.self, context: context)
              return UserResponse(from: user)
          }

          func current(_ request: Request, context: AppRequestContext) throws -> UserResponse {
              let user = try context.requireIdentity()
              return UserResponse(from: user)
          }
      }
      SWIFT

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(line : Int32) { Endpoint.new("/x", "GET", [] of Param, Details.new(PathInfo.new(controller, line))) }
    create, current = at.call(3), at.call(5)
    SwiftAuthTagger.new(noir_options).perform([create, current])

    create.tags.should be_empty
    current.tags.map(&.description).should eq(["Protected by Hummingbird requireIdentity"])
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  it "treats a redirectMiddleware group as guarded" do
    tmpdir = File.tempname("swift_redirect_mw")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "routes.swift")
    File.write(routes, <<-SWIFT)
      func routes(_ app: Application) throws {
          let sessions = app.grouped(User.sessionAuthenticator())
          sessions.get("login", use: WebController.login)
          let members = sessions.grouped(User.redirectMiddleware(path: "/login"))
          members.get("account", use: WebController.account)
      }
      SWIFT

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    at = ->(line : Int32) { Endpoint.new("/x", "GET", [] of Param, Details.new(PathInfo.new(routes, line))) }
    login, account = at.call(3), at.call(5)
    SwiftAuthTagger.new(noir_options).perform([login, account])

    login.tags.should be_empty
    account.tags.map(&.description).should eq(["Protected by Vapor redirectMiddleware"])
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end
end
