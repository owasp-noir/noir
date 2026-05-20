require "../../spec_helper"
require "../../../src/analyzer/analyzers/swift/vapor"

describe "swift vapor analyzer" do
  it "tracks grouped route prefixes and named handlers" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    instance = Analyzer::Swift::Vapor.new(options)

    temp_dir = File.tempname("swift_vapor_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Vapor

      func createUser(
          _ req: Request
      ) throws -> EventLoopFuture<User> {
          let tenant = req.parameters.get("tenantID")
          let payload = try req.content.decode(CreateUser.self)
          return UserService.create(tenant, payload, on: req.db)
      }

      func routes(_ app: Application) throws {
          app.group("api", ":tenantID") { tenantRoutes in
              tenantRoutes.post("users", use: createUser)
          }

          let admin = app.grouped("admin", "v1")
          admin.on(.GET, "reports") { req async throws in
              let token = req.headers["Authorization"].first
              return try await ReportService.list(token)
          }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    create_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/api/:tenantID/users" }
    report_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/admin/v1/reports" }

    create_endpoint.should_not be_nil
    report_endpoint.should_not be_nil

    if create_endpoint
      create_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"tenantID", "path"})
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
    instance = Analyzer::Swift::Vapor.new(options)

    temp_dir = File.tempname("swift_vapor_inline_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Vapor

      func routes(_ app: Application) throws {
          app.get("hello") { req in Foo.make(req, "bar") }
          app.on(.POST, "submit", body: .collect(maxSize: "1mb")) { req in Foo.make(req, "baz") }
      }
      SWIFT

    endpoints = instance.analyze_file(temp_file)
    endpoints.map(&.url).should contain("/hello")
    endpoints.map(&.url).should contain("/submit")
    endpoints.map(&.url).should_not contain("/hello/bar")
    endpoints.map(&.url).should_not contain("/submit/1mb/baz")
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
