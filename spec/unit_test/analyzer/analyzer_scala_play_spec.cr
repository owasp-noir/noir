require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/scala/play"

describe "scala play analyzer" do
  it "extracts controller params from injected async actions with body parsers" do
    options = create_test_options

    temp_dir = File.tempname("scala_play_test")
    conf_dir = File.join(temp_dir, "conf")
    controller_dir = File.join(temp_dir, "app", "controllers")
    Dir.mkdir_p(conf_dir)
    Dir.mkdir_p(controller_dir)

    routes_path = File.join(conf_dir, "routes")
    routes_content = <<-ROUTES
      POST /users/:id controllers.HomeController.create(id: Long)
      ROUTES
    File.write(routes_path, routes_content)

    controller_path = File.join(controller_dir, "HomeController.scala")
    controller_content = <<-SCALA
      package controllers

      import javax.inject._
      import play.api.mvc._

      @Singleton
      class HomeController @Inject()(cc: ControllerComponents) extends AbstractController(cc) {
        def create(id: Long) = Action.async(parse.json) { implicit request =>
          val auth = request.headers.get("Authorization")
          val session = request.cookies.get("session")
          Future.successful(Ok)
        }
      }
      SCALA
    File.write(controller_path, controller_content)

    CodeLocator.instance.clear_all
    CodeLocator.instance.register_file(routes_path, routes_content)
    CodeLocator.instance.register_file(controller_path, controller_content)

    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    endpoints = Analyzer::Scala::Play.new(options).analyze
    endpoint = endpoints.find { |e| e.method == "POST" && e.url == "/users/:id" }

    endpoint.should_not be_nil

    if endpoint
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"id", "path"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"Authorization", "header"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"session", "cookie"})
      endpoint.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
    end
  ensure
    CodeLocator.instance.clear_all
    File.delete(routes_path) if routes_path && File.exists?(routes_path)
    File.delete(controller_path) if controller_path && File.exists?(controller_path)
    Dir.delete(controller_dir) if controller_dir && Dir.exists?(controller_dir)
    app_dir = temp_dir ? File.join(temp_dir, "app") : nil
    Dir.delete(app_dir) if app_dir && Dir.exists?(app_dir)
    Dir.delete(conf_dir) if conf_dir && Dir.exists?(conf_dir)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "extracts Scala 3 indentation method bodies without sibling bleed" do
    options = create_test_options
    options["include_callee"] = YAML::Any.new(true)

    temp_dir = File.tempname("scala_play_scala3_test")
    conf_dir = File.join(temp_dir, "conf")
    controller_dir = File.join(temp_dir, "app", "controllers")
    Dir.mkdir_p(conf_dir)
    Dir.mkdir_p(controller_dir)

    routes_path = File.join(conf_dir, "routes")
    routes_content = <<-ROUTES
      GET  /api               controllers.Main.api
      POST /unsub/:channel    controllers.Main.unsub(channel)
      POST /submit            controllers.Main.submit
      ROUTES
    File.write(routes_path, routes_content)

    # Scala 3 significant-indentation controller: a brace-less class whose
    # colon-block actions (`= AuthOrScoped():`, `= Action(parse.json):`) sit
    # next to a brace-block action. Pre-fix, the colon-block `api` swallowed
    # the following `unsub` brace body, misattributing its callees.
    controller_path = File.join(controller_dir, "Main.scala")
    controller_content = <<-SCALA
      package controllers

      import play.api.mvc.*
      import play.api.libs.json.*

      final class Main(env: Env) extends BaseController:

        def api = AuthOrScoped():
          apiOutput(buildList(30))

        def unsub(channel: String) = Action { request =>
          val trace = request.headers.get("X-Trace-Id")
          env.timeline.unsubApi.set(channel)
          Ok("done")
        }

        def submit = Action(parse.json): request =>
          val token = request.headers.get("Authorization")
          val sid = request.cookies.get("session")
          Ok(Json.toJson(token))
      SCALA
    File.write(controller_path, controller_content)

    CodeLocator.instance.clear_all
    CodeLocator.instance.register_file(routes_path, routes_content)
    CodeLocator.instance.register_file(controller_path, controller_content)

    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    endpoints = Analyzer::Scala::Play.new(options).analyze

    api = endpoints.find { |e| e.method == "GET" && e.url == "/api" }
    api.should_not be_nil
    if api
      callee_names = api.callees.map(&.name)
      callee_names.should contain("apiOutput")
      # The colon-block body must not bleed into the following brace method.
      callee_names.should_not contain("env.timeline.unsubApi.set")
    end

    unsub = endpoints.find { |e| e.method == "POST" && e.url == "/unsub/:channel" }
    unsub.should_not be_nil
    if unsub
      unsub.params.map { |p| {p.name, p.param_type} }.should contain({"channel", "path"})
      unsub.params.map { |p| {p.name, p.param_type} }.should contain({"X-Trace-Id", "header"})
      unsub.callees.map(&.name).should contain("env.timeline.unsubApi.set")
    end

    submit = endpoints.find { |e| e.method == "POST" && e.url == "/submit" }
    submit.should_not be_nil
    if submit
      submit.params.map { |p| {p.name, p.param_type} }.should contain({"Authorization", "header"})
      submit.params.map { |p| {p.name, p.param_type} }.should contain({"session", "cookie"})
      submit.params.map { |p| {p.name, p.param_type} }.should contain({"body", "json"})
      submit.callees.map(&.name).should contain("Json.toJson")
    end
  ensure
    CodeLocator.instance.clear_all
    File.delete(routes_path) if routes_path && File.exists?(routes_path)
    File.delete(controller_path) if controller_path && File.exists?(controller_path)
    Dir.delete(controller_dir) if controller_dir && Dir.exists?(controller_dir)
    app_dir = temp_dir ? File.join(temp_dir, "app") : nil
    Dir.delete(app_dir) if app_dir && Dir.exists?(app_dir)
    Dir.delete(conf_dir) if conf_dir && Dir.exists?(conf_dir)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end

  it "resolves included routes relative to the including routes file" do
    options = create_test_options

    temp_dir = File.tempname("scala_play_multi_module_test")
    module_a_conf = File.join(temp_dir, "module-a", "conf")
    module_b_conf = File.join(temp_dir, "module-b", "conf")
    Dir.mkdir_p(module_a_conf)
    Dir.mkdir_p(module_b_conf)

    a_routes = File.join(module_a_conf, "routes")
    a_admin_routes = File.join(module_a_conf, "admin.routes")
    b_routes = File.join(module_b_conf, "routes")
    b_admin_routes = File.join(module_b_conf, "admin.routes")

    File.write(a_routes, "-> /admin admin.Routes\n")
    File.write(a_admin_routes, "GET /a controllers.Admin.a\n")
    File.write(b_routes, "-> /admin admin.Routes\n")
    File.write(b_admin_routes, "GET /b controllers.Admin.b\n")

    CodeLocator.instance.clear_all
    CodeLocator.instance.register_file(a_routes, File.read(a_routes))
    CodeLocator.instance.register_file(a_admin_routes, File.read(a_admin_routes))
    CodeLocator.instance.register_file(b_routes, File.read(b_routes))
    CodeLocator.instance.register_file(b_admin_routes, File.read(b_admin_routes))

    options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
    endpoints = Analyzer::Scala::Play.new(options).analyze

    endpoints.map(&.url).should contain("/admin/a")
    endpoints.map(&.url).should contain("/admin/b")
    endpoints.map(&.url).should_not contain("/a")
    endpoints.map(&.url).should_not contain("/b")
  ensure
    CodeLocator.instance.clear_all
    [a_routes, a_admin_routes, b_routes, b_admin_routes].each do |path|
      File.delete(path) if path && File.exists?(path)
    end
    Dir.delete(module_a_conf) if module_a_conf && Dir.exists?(module_a_conf)
    Dir.delete(module_b_conf) if module_b_conf && Dir.exists?(module_b_conf)
    module_a = temp_dir ? File.join(temp_dir, "module-a") : nil
    module_b = temp_dir ? File.join(temp_dir, "module-b") : nil
    Dir.delete(module_a) if module_a && Dir.exists?(module_a)
    Dir.delete(module_b) if module_b && Dir.exists?(module_b)
    Dir.delete(temp_dir) if temp_dir && Dir.exists?(temp_dir)
  end
end
