require "../../spec_helper"
require "../../../src/analyzer/analyzers/scala/tapir.cr"

describe "scala tapir route extraction" do
  it "extracts methods, path matchers, and inputs from a tapir endpoint chain" do
    options = create_test_options
    instance = Analyzer::Scala::Tapir.new(options)

    temp_dir = File.tempname("scala_tapir_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Endpoints.scala")

    File.write(temp_file, <<-SCALA)
      import sttp.tapir._

      object Endpoints {
        val getUser =
          endpoint
            .get
            .in("users" / path[Int]("id"))
            .in(query[Option[String]]("include"))
            .in(header[String]("Authorization"))
            .out(jsonBody[User])

        val createUser = endpoint.post.in("users").in(jsonBody[User])
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    get_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/users/{id}" }
    post_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/users" }

    get_endpoint.should_not be_nil
    post_endpoint.should_not be_nil

    if get_endpoint
      params = get_endpoint.params.map { |p| {p.name, p.param_type} }
      params.should contain({"id", "path"})
      params.should contain({"include", "query"})
      params.should contain({"Authorization", "header"})
    end

    if post_endpoint
      post_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "supports the .in-before-method ordering" do
    options = create_test_options
    instance = Analyzer::Scala::Tapir.new(options)

    temp_dir = File.tempname("scala_tapir_order_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Endpoints.scala")

    File.write(temp_file, <<-SCALA)
      import sttp.tapir._

      object Endpoints {
        val pingEndpoint = endpoint.in("ping").get.out(stringBody)
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    endpoints.find { |e| e.method == "GET" && e.url == "/ping" }.should_not be_nil
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
