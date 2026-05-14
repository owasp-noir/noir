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
