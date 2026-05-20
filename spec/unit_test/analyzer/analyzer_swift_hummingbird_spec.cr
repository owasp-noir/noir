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
end
