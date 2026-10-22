require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

private def scan_params(files : Hash(String, String)) : Array(String)
  root = File.tempname("noir-python-comment-params")
  files.each do |path, content|
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.flat_map(&.params.map(&.name))
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(root) if root && Dir.exists?(root)
end

private def assert_comment_free(files : Hash(String, String))
  names = scan_params(files)
  names.should contain("real")
  names.should_not contain("commented")
  names.should_not contain("trailing")
end

# A `#` comment in a handler body is not a request read, whether it opens the
# line or trails real code.
describe "Python handler-body comments" do
  it "drops commented reads in sanic" do
    source = <<-PY
      from sanic import Sanic
      from sanic.response import json
      app = Sanic("a")

      @app.get("/x")
      async def x(request):
          # request.args.get("commented")
          return json({"v": request.args.get("real")})  # request.args.get("trailing")
      PY
    assert_comment_free({"requirements.txt" => "sanic\n", "app.py" => source})
  end

  it "drops commented reads in fastapi" do
    source = <<-PY
      from fastapi import FastAPI, Request
      app = FastAPI()

      @app.get("/x")
      async def x(request: Request):
          # request.query_params.get("commented")
          return {"v": request.query_params.get("real")}  # request.headers["trailing"]
      PY
    assert_comment_free({"requirements.txt" => "fastapi\n", "main.py" => source})
  end

  it "drops commented reads in tornado" do
    source = <<-PY
      import tornado.web
      class H(tornado.web.RequestHandler):
          def get(self):
              # self.get_argument("commented")
              self.write(self.get_argument("real"))  # self.get_argument("trailing")
      app = tornado.web.Application([(r"/x", H)])
      PY
    assert_comment_free({"requirements.txt" => "tornado\n", "app.py" => source})
  end

  it "drops commented reads in starlette" do
    source = <<-PY
      from starlette.applications import Starlette
      from starlette.routing import Route
      async def x(request):
          # request.query_params["commented"]
          return request.query_params["real"]  # request.query_params["trailing"]
      app = Starlette(routes=[Route("/x", x)])
      PY
    assert_comment_free({"requirements.txt" => "starlette\n", "app.py" => source})
  end

  it "drops commented reads in django" do
    views = <<-PY
      from django.http import HttpResponse
      def x(request):
          # legacy: request.GET.get("commented")
          v = request.GET.get("real")  # request.GET.get("trailing")
          return HttpResponse()
      PY
    assert_comment_free({
      "manage.py"        => "import os\nos.environ.setdefault(\"DJANGO_SETTINGS_MODULE\", \"proj.settings\")\n",
      "proj/__init__.py" => "",
      "proj/settings.py" => "ROOT_URLCONF = \"proj.urls\"\n",
      "proj/urls.py"     => "from django.urls import path\nfrom app import views\nurlpatterns = [path(\"x/\", views.x)]\n",
      "app/__init__.py"  => "",
      "app/views.py"     => views,
    })
  end
end
