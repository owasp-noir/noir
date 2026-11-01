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

  it "extracts callees from string interpolation holes in handler body" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)
    instance = Analyzer::Scala::Scalatra.new(options)

    temp_dir = File.tempname("scala_scalatra_interp_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "InterpServlet.scala")

    File.write(temp_file, <<-SCALA)
      import org.scalatra._

      class InterpServlet extends ScalatraServlet {
        get("/x") {
          val html = s"${avatar(u)} <b>@${StringUtil.escapeHtml(
            StringUtil.cutTail(name, 10))}</b>"
          val single = s"v ${svc.lookup(x)}"
          html
        }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    endpoint = endpoints.find { |e| e.method == "GET" && e.url == "/x" }
    endpoint.should_not be_nil

    if endpoint
      callee_names = endpoint.callees.map(&.name)
      callee_names.should contain("StringUtil.escapeHtml")
      callee_names.should contain("StringUtil.cutTail")
      callee_names.should contain("svc.lookup")
    end
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "finds routes after an unterminated interpolation hole" do
    options = create_test_options
    instance = Analyzer::Scala::Scalatra.new(options)

    temp_dir = File.tempname("scala_scalatra_unclosed_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "UnclosedServlet.scala")

    File.write(temp_file, <<-SCALA)
      import org.scalatra._

      class BrokenServlet extends ScalatraServlet {
        val bad = s"oops ${ foo(

        def nextRoute = get("/recovered1") { "ok" }
      }

      class WorkingServlet extends ScalatraServlet {
        val bad2 = s"oops2 ${ bar(
      }

      class FinalServlet extends ScalatraServlet {
        get("/recovered2") { "ok" }
      }
      SCALA

    endpoints = instance.analyze_file(temp_file)
    endpoints.map(&.url).should contain("/recovered1")
    endpoints.map(&.url).should contain("/recovered2")
  ensure
    File.delete(temp_file) if temp_file && File.exists?(temp_file)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
