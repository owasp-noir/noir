require "../../spec_helper"
require "../../../src/analyzer/analyzers/scala/scalatra"

describe "scala scalatra analyzer" do
  it "accepts route definitions with extra route arguments" do
    options = create_test_options
    instance = Analyzer::Scala::Scalatra.new(options)

    temp_dir = File.tempname("scala_scalatra_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "MyServlet.scala")

    File.write(temp_file, <<-SCALA)
      import org.scalatra._

      class MyServlet extends ScalatraServlet {
        get("/users/:id", request.getHeader("X-Enabled") != null) {
          val expand = params("expand")
          val auth = request.getHeader("Authorization")
          s"user $expand $auth"
        }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/users/:id" }

    endpoint.should_not be_nil

    if endpoint
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"id", "path"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"expand", "query"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"Authorization", "header"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
