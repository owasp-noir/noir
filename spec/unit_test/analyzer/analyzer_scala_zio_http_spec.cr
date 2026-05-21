require "../../spec_helper"
require "../../../src/analyzer/analyzers/scala/zio_http.cr"

describe "scala zio http route extraction" do
  it "parses Method.X / segments with literal and typed path matchers" do
    options = create_test_options
    instance = Analyzer::Scala::ZioHttp.new(options)

    temp_dir = File.tempname("scala_zio_http_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Routes.scala")

    File.write(temp_file, <<-SCALA)
      import zio.http._

      object Routes {
        val routes = Routes(
          Method.GET / "users" -> handler(Response.text("ok")),
          Method.GET / "users" / int("userId") -> handler { (userId: Int, req: Request) =>
            Response.text(userId.toString)
          },
          Method.POST / "api" / "v1" / "items" -> handler { (req: Request) =>
            req.body.to[CreateItem].map(item => Response.text(item.name))
          },
        )
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    list_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/users" }
    show_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/users/{userId}" }
    create_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/api/v1/items" }

    list_endpoint.should_not be_nil
    show_endpoint.should_not be_nil
    create_endpoint.should_not be_nil

    if show_endpoint
      show_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"userId", "path"})
    end

    if create_endpoint
      create_endpoint.params.map { |p| {p.name, p.value, p.param_type} }.should contain({"body", "CreateItem", "json"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "extracts query parameters and headers from handler bodies" do
    options = create_test_options
    instance = Analyzer::Scala::ZioHttp.new(options)

    temp_dir = File.tempname("scala_zio_http_params_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Routes.scala")

    File.write(temp_file, <<-SCALA)
      import zio.http._

      object Routes {
        val routes = Routes(
          Method.GET / "search" -> handler { (req: Request) =>
            val q = req.url.queryParam("q")
            val auth = req.headers.get("Authorization")
            Response.text(q.getOrElse(""))
          },
        )
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    search_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/search" }

    search_endpoint.should_not be_nil

    if search_endpoint
      param_pairs = search_endpoint.params.map { |p| {p.name, p.param_type} }
      param_pairs.should contain({"q", "query"})
      param_pairs.should contain({"Authorization", "header"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
