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
end
