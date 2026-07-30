require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/analyzer/analyzers/python/flask"
require "../../../src/analyzer/analyzers/python/aiohttp"
require "file_utils"

# The relevance gate is the only thing keeping an analyzer off a competing
# framework's handler module — every Python analyzer is handed every `.py`
# file in the scan.
class FlaskRelevanceHarness < Analyzer::Python::Flask
  def relevant?(source : String) : Bool
    flask_relevant_source?(source)
  end
end

class AiohttpRelevanceHarness < Analyzer::Python::Aiohttp
  def relevant?(source : String) : Bool
    aiohttp_relevant_source?(source)
  end
end

private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.clear("file_map")
end

private def tech_sources(endpoints : Array(Endpoint), technology : String) : Array(String)
  endpoints.compact_map do |endpoint|
    next unless endpoint.details.technology == technology
    endpoint.details.code_paths.first?.try(&.path)
  end.uniq!
end

describe "analyzer project scoping (csharp, python)" do
  it "keeps ASP.NET Core MVC and classic ASP.NET MVC off each other's controllers" do
    # Both spell a controller almost identically — `public class UserController
    # : Controller` with `[HttpGet]` actions — and both analyzers see every
    # `.cs` file. The namespaces are mutually exclusive and are what tell them
    # apart.
    root = File.tempname("noir-csharp-scope")

    begin
      legacy = File.join(root, "Legacy")
      FileUtils.mkdir_p(File.join(legacy, "Controllers"))
      File.write(File.join(legacy, "packages.config"), %(<packages><package id="Microsoft.AspNet.Mvc" /></packages>))
      File.write(File.join(legacy, "Controllers", "ProductController.cs"), <<-CS)
        using System.Web.Mvc;

        namespace Legacy.Controllers
        {
            public class ProductController : Controller
            {
                public ActionResult List() { return View(); }
            }
        }
        CS

      modern = File.join(root, "Modern")
      FileUtils.mkdir_p(File.join(modern, "Controllers"))
      File.write(File.join(modern, "MyApp.csproj"), %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>))
      File.write(File.join(modern, "Controllers", "UsersController.cs"), <<-CS)
        using Microsoft.AspNetCore.Mvc;

        namespace Modern.Controllers
        {
            [ApiController]
            [Route("api/[controller]")]
            public class UsersController : ControllerBase
            {
                [HttpGet("GetAll")]
                public IActionResult GetAll() => Ok();
            }
        }
        CS

      endpoints = scan_tree(root)

      core_sources = tech_sources(endpoints, "cs_aspnet_core_mvc")
      core_sources.any?(&.includes?("/Modern/")).should be_true
      core_sources.any?(&.includes?("/Legacy/")).should be_false

      legacy_sources = tech_sources(endpoints, "cs_aspnet_mvc")
      legacy_sources.any?(&.includes?("/Legacy/")).should be_true
      legacy_sources.any?(&.includes?("/Modern/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  describe "Python competing-import guards" do
    flask = FlaskRelevanceHarness.new(create_test_options)
    aiohttp = AiohttpRelevanceHarness.new(create_test_options)

    it "still claims a real Flask module" do
      flask.relevant?(<<-PY).should be_true
        from flask import Flask

        app = Flask(__name__)

        @app.route("/health")
        def health():
            return "ok"
        PY
    end

    it "keeps Flask off Django Ninja, Bottle and aiohttp modules" do
      # `@api.get("/x")` and `@app.get("/x")` are the same line in every
      # decorator-based Python framework. Flask already refused files
      # importing fastapi/sanic/litestar/… — `ninja`, `bottle` and `aiohttp`
      # were missing, so their handler modules were relabelled `python_flask`
      # with Flask-shaped (usually empty) params.
      flask.relevant?(<<-PY).should be_false
        from ninja import NinjaAPI

        api = NinjaAPI()

        @api.get("/items")
        def items(request):
            return []
        PY

      flask.relevant?(<<-PY).should be_false
        from bottle import Bottle

        app = Bottle()

        @app.get("/dashboard")
        def dashboard():
            return "ok"
        PY

      flask.relevant?(<<-PY).should be_false
        from aiohttp import web

        routes = web.RouteTableDef()

        @routes.get("/stats")
        async def stats(request):
            return web.Response(text="ok")
        PY
    end

    it "keeps aiohttp off a Sanic module but still claims its own" do
      # Sanic has an `app.add_route(handler, "/path")` of its own — argument
      # order reversed from aiohttp's, so aiohttp read the handler name as the
      # route. The bare `.add_route(` marker cannot tell the two apart; the
      # import can.
      aiohttp.relevant?(<<-PY).should be_false
        from sanic import Sanic

        app = Sanic("test_app")

        app.add_route(create_report, "/create", methods=["POST"])

        @app.get("/status")
        async def status(request):
            return response.json({})
        PY

      aiohttp.relevant?(<<-PY).should be_true
        from aiohttp import web

        routes = web.RouteTableDef()

        @routes.get("/stats")
        async def stats(request):
            return web.Response(text="ok")
        PY
    end
  end
end
