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

  it "composes chained grouped() calls and verbs called on a group expression" do
    instance = Analyzer::Swift::Vapor.new(create_test_options)

    temp_dir = File.tempname("swift_vapor_chain_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Vapor

      func routes(_ app: Application) throws {
          app.grouped("inline").on(.GET, "d") { req in "d" }
          let v2 = app.grouped("api").grouped("v2")
          v2.get("x") { req in "x" }
          app.grouped("m").group("n") { r in
              r.get("o") { req in "o" }
          }
          app.grouped(AuthMiddleware()).grouped("secure").delete("s") { req in "s" }
      }
      SWIFT

    urls = instance.analyze_file(temp_file).map { |e| "#{e.method} #{e.url}" }
    urls.should contain("GET /inline/d")
    urls.should contain("GET /api/v2/x")
    urls.should contain("GET /m/n/o")
    urls.should contain("DELETE /secure/s")
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "does not leak params from code after the route into it" do
    instance = Analyzer::Swift::Vapor.new(create_test_options)

    temp_dir = File.tempname("swift_vapor_leak_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Vapor

      func routes(_ app: Application) throws {
          app.get("ping", use: ping)
          app.get("one") { req in req.headers["X-Inline"] }
          app.get("two") { req -> String in
              let id = req.parameters.get("id")
              let payload = try req.content.decode(Payload.self)
              return "ok"
          }
      }

      func ping(req: Request) throws -> String { return "pong" }

      func unrelated(req: Request) throws -> String {
          let t = req.headers["X-Secret-Token"]
          let a = req.query["admin"]
          return "x"
      }

      struct TodoController: RouteCollection {
          func boot(routes: RoutesBuilder) throws {
              let todos = routes.grouped("todos")
              todos.post(use: self.create)
              todos.group(":todoID") { todo in
                  todo.delete(use: delete)
              }
          }

          func create(req: Request) async throws -> Todo {
              let todo = try req.content.decode(Todo.self)
              return todo
          }

          func delete(req: Request) async throws -> HTTPStatus {
              return .noContent
          }
      }
      SWIFT

    params = instance.analyze_file(temp_file).to_h { |e| {"#{e.method} #{e.url}", e.params.map { |p| "#{p.param_type}:#{p.name}" }.sort!} }
    params["GET /ping"].should eq([] of String)
    params["GET /one"].should eq(["header:X-Inline"])
    params["GET /two"].should eq(["json:body", "path:id"])
    params["POST /todos"].should eq(["json:body"])
    params["DELETE /todos/:todoID"].should eq(["path:todoID"])
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "ignores routes inside block comments and multi-line strings" do
    instance = Analyzer::Swift::Vapor.new(create_test_options)

    temp_dir = File.tempname("swift_vapor_comment_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Vapor

      func routes(_ app: Application) throws {
          app.get("live") { req in "ok" }
          /*
          app.post("block-commented") { req in "x" }
          */
          /* app.put("inline-comment") { req in "x" } */ app.patch("after-comment") { req in "y" }
          // app.delete("line-commented") { req in "x" }
          let doc = """
          app.get("in-string") { req in "x" }
          """
          app.get("api//v2") { req in "z" }
      }
      SWIFT

    instance.analyze_file(temp_file).map { |e| "#{e.method} #{e.url}" }.sort!.should eq(
      ["GET /api/v2", "GET /live", "PATCH /after-comment"])
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
