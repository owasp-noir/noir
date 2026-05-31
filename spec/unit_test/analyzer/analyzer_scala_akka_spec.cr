require "../../spec_helper"
require "../../../src/analyzer/analyzers/scala/akka.cr"

describe "scala akka callee extraction" do
  it "keeps callees scoped to the matched HTTP method block" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    instance = Analyzer::Scala::Akka.new(options)

    temp_dir = File.tempname("scala_akka_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Routes.scala")

    File.write(temp_file, <<-SCALA)
      import akka.http.scaladsl.server.Directives._

      object Routes {
        val route =
          path("users") {
            concat(
              get {
                UserService.list()
              },
              post {
                UserService.create()
              }
            )
          }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    get_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/users" }
    post_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/users" }

    get_endpoint.should_not be_nil
    post_endpoint.should_not be_nil

    if get_endpoint && post_endpoint
      get_names = get_endpoint.callees.map(&.name)
      post_names = post_endpoint.callees.map(&.name)

      get_names.should contain("UserService.list")
      get_names.should_not contain("UserService.create")
      post_names.should contain("UserService.create")
      post_names.should_not contain("UserService.list")
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end

describe "scala akka route extraction" do
  it "tracks composite path prefixes, matcher names, and pathEnd routes" do
    options = create_test_options
    instance = Analyzer::Scala::Akka.new(options)

    temp_dir = File.tempname("scala_akka_routes_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Routes.scala")

    File.write(temp_file, <<-SCALA)
      import akka.http.scaladsl.server.Directives._

      object Routes {
        val route =
          pathPrefix("api" / "v1" / Segment) { tenantId =>
            concat(
              pathEndOrSingleSlash {
                get {
                  complete("tenant root")
                }
              },
              path("users" / JavaUUID) { userId =>
                get {
                  complete(userId.toString)
                }
              }
            )
          }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    root_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/api/v1/{tenantId}" }
    user_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/api/v1/{tenantId}/users/{userId}" }

    root_endpoint.should_not be_nil
    user_endpoint.should_not be_nil

    if root_endpoint
      root_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"tenantId", "path"})
    end

    if user_endpoint
      user_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"tenantId", "path"})
      user_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"userId", "path"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "keeps params scoped to inline sibling method directives" do
    options = create_test_options
    instance = Analyzer::Scala::Akka.new(options)

    temp_dir = File.tempname("scala_akka_inline_params_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "Routes.scala")

    File.write(temp_file, <<-SCALA)
      import akka.http.scaladsl.server.Directives._

      object Routes {
        val route =
          pathPrefix("orders") {
            pathEndOrSingleSlash {
              get(complete("orders")) ~
              (post & entity(as[Order])) { order =>
                complete("created")
              }
            }
          }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    get_endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/orders" }
    post_endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/orders" }

    get_endpoint.should_not be_nil
    post_endpoint.should_not be_nil

    if get_endpoint && post_endpoint
      get_endpoint.params.any? { |p| p.name == "body" }.should be_false
      post_endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
