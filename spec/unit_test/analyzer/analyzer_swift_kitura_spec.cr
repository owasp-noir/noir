require "../../spec_helper"
require "../../../src/analyzer/analyzers/swift/kitura"

describe "swift kitura analyzer" do
  it "extracts params from named route handlers without callee mode" do
    options = create_test_options
    instance = Analyzer::Swift::Kitura.new(options)

    temp_dir = File.tempname("swift_kitura_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "routes.swift")

    File.write(temp_file, <<-SWIFT)
      import Kitura

      func createUser(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
          let id = request.parameters["id"]
          let expand = request.queryParameters["expand"]
          let auth = request.headers["Authorization"]
          let payload = try request.read(as: User.self)
          try response.send(payload).end()
          next()
      }

      let router = Router()
      router.post("/users/:id", handler: createUser)
      SWIFT

    endpoint = instance.analyze_file(temp_file).find { |e| e.method == "POST" && e.url == "/users/:id" }
    endpoint.should_not be_nil

    if endpoint
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"id", "path"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"expand", "query"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"Authorization", "header"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
