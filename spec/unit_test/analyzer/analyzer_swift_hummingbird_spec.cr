require "../../spec_helper"
require "../../../src/analyzer/analyzers/swift/hummingbird"

describe "swift hummingbird analyzer" do
  it "tracks grouped route prefixes and named handlers" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    instance = Analyzer::Swift::Hummingbird.new(options)

    temp_dir = File.tempname("swift_hummingbird_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Hummingbird

      func createUser(
          _ request: Request,
          context: BasicRequestContext
      ) async throws -> User {
          let id = try context.parameters.require("id", as: String.self)
          let payload = try await request.decode(as: CreateUser.self, context: context)
          return try await UserService.create(id, payload)
      }

      func routes(_ router: Router<BasicRequestContext>) {
          router.group("api") { api in
              api.post("users/:id", use: createUser)
          }

          let admin = router.group("admin")
          admin.get("reports") { request, context async throws in
              let token = request.headers["Authorization"]
              return try await ReportService.list(token)
          }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    create_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/api/users/:id" }
    report_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/admin/reports" }

    create_endpoint.should_not be_nil
    report_endpoint.should_not be_nil

    if create_endpoint
      create_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"id", "path"})
      create_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
      create_endpoint.callees.map(&.name).should contain("UserService.create")
    end

    if report_endpoint
      report_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"Authorization", "header"})
      report_endpoint.callees.map(&.name).should contain("ReportService.list")
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "does not read one-line closure string literals as route segments" do
    options = create_test_options
    instance = Analyzer::Swift::Hummingbird.new(options)

    temp_dir = File.tempname("swift_hummingbird_inline_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Hummingbird

      func routes(_ router: Router<BasicRequestContext>) {
          router.get("hello") { request, context in Foo.make(request, "bar") }
          router.group("api") { api in api.get("status") { request, context in Foo.make(request, "baz") } }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    endpoints.map(&.url).should contain("/hello")
    endpoints.map(&.url).should contain("/api/status")
    endpoints.map(&.url).should_not contain("/hello/bar")
    endpoints.map(&.url).should_not contain("/api/baz/status")
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "ignores look-alike calls on non-router receivers" do
    options = create_test_options
    instance = Analyzer::Swift::Hummingbird.new(options)

    temp_dir = File.tempname("swift_hummingbird_receiver_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Hummingbird

      func routes(_ router: Router<BasicRequestContext>) {
          let level = environment.get("LOG_LEVEL")
          let token = sessionStorage.get(key: "session")
          _ = try await repository.delete(id: identifier)
          _ = try await database.schema("todos").delete()

          router.get("ping") { _, _ in "pong" }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    endpoints.map(&.url).should eq(["/ping"])
    endpoints.map(&.method).should eq(["GET"])
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "resolves fluent builder chains, .on, head and ws verbs" do
    options = create_test_options
    instance = Analyzer::Swift::Hummingbird.new(options)

    temp_dir = File.tempname("swift_hummingbird_chain_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Hummingbird

      func routes(_ router: Router<BasicRequestContext>) {
          router.group("api")
              .get("items", use: listItems)
              .post("items", use: createItems)

          router.on("legacy", method: .GET) { _, _ in "ok" }
          router.head("health") { _, _ in .ok }
          router.ws("live") { _, _ in .upgrade([:]) }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", "/api/items"})
    pairs.should contain({"POST", "/api/items"})
    pairs.should contain({"GET", "/legacy"})
    pairs.should contain({"HEAD", "/health"})
    pairs.should contain({"GET", "/live"})
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
