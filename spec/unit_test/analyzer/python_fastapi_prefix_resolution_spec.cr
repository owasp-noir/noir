require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/analyzer/analyzers/python/fastapi"
require "file_utils"

class FastAPIImportRootSpecHarness < Analyzer::Python::FastAPI
  def project_root(path : String) : String
    fastapi_project_root_for(path)
  end
end

describe "FastAPI prefix resolution" do
  it "keeps a nested project marker root in the scan's relative path form" do
    root = "spec/functional_test/fixtures/python/fastapi_nested_app_import"
    project_root = File.join(root, "deep_case")
    app_file = File.join(project_root, "a", "b", "api_app.py")
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])

    locator = CodeLocator.instance
    previous_bases = locator.scan_base_paths
    begin
      locator.clear_all
      locator.scan_base_paths = [root]
      locator.register_path(File.join(project_root, "requirements.txt"))

      FastAPIImportRootSpecHarness.new(options).project_root(app_file).should eq(project_root)
    ensure
      locator.clear_all
      locator.scan_base_paths = previous_bases
    end
  end

  it "keeps the app-relative import root when a project uses a src layout" do
    root = File.tempname("noir-fastapi-src-root")
    app_dir = File.join(root, "src", "dispatch")
    app_file = File.join(app_dir, "main.py")
    marker = File.join(root, "pyproject.toml")
    Dir.mkdir_p(app_dir)
    File.write(marker, "[project]\n")
    File.write(File.join(app_dir, "__init__.py"), "")
    File.write(File.join(app_dir, "api.py"), "router = object()\n")
    File.write(app_file, "from dispatch.api import router\napp = FastAPI()\n")
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])

    locator = CodeLocator.instance
    previous_bases = locator.scan_base_paths
    begin
      locator.clear_all
      locator.scan_base_paths = [root]
      locator.register_path(marker)

      FastAPIImportRootSpecHarness.new(options).project_root(app_file).should eq(File.join(root, "src"))
    ensure
      locator.clear_all
      locator.scan_base_paths = previous_bases
      FileUtils.rm_rf(root)
    end
  end

  it "keeps safe tails, marks unread prefixes, and preserves resolved nested mounts" do
    root = File.tempname("noir-fastapi-prefix")
    Dir.mkdir_p(root)
    File.write(File.join(root, "requirements.txt"), "fastapi\n")
    File.write(File.join(root, "constants.py"), "API_PREFIX = \"/constant\"\n")
    File.write(File.join(root, "settings.py"), <<-PY)
      from pydantic_settings import BaseSettings

      class Settings(BaseSettings):
          API_V1_STR: str = "/api/v1"

      settings = Settings()
      PY
    File.write(File.join(root, "api.py"), <<-PY)
      import os
      from fastapi import APIRouter

      BASE = os.getenv("API_BASE", "")
      external = APIRouter(prefix=BASE + "/external")
      fstring = APIRouter(prefix=f"{settings.RUNTIME_PREFIX}/f-v1")
      outer = APIRouter(prefix="/outer")
      outer.include_router(external, prefix=BASE + "/nested")

      @external.get("/route")
      def external_route():
          return {}

      @fstring.get("/fstring")
      def fstring_route():
          return {}
      PY
    File.write(File.join(root, "main.py"), <<-PY)
      import os
      from fastapi import APIRouter, FastAPI
      from api import outer
      from constants import API_PREFIX
      from settings import settings

      BASE = os.getenv("API_BASE", "")
      app = FastAPI()
      literal = APIRouter(prefix="/literal")
      constant = APIRouter(prefix=API_PREFIX)
      defaulted = APIRouter(prefix=settings.API_V1_STR)
      tail = APIRouter(prefix=BASE + "/v1")
      unread = APIRouter(prefix=settings.RUNTIME_PREFIX)
      variable = APIRouter(prefix=UNRESOLVED_PREFIX)
      leading_runtime = APIRouter(prefix="/leading" + settings.RUNTIME_SUFFIX)
      env = APIRouter(prefix=os.environ["UNREAD_PREFIX"])
      call = APIRouter(prefix=make_prefix())
      include_unread = APIRouter()
      parent = APIRouter(prefix="/parent")
      child = APIRouter(prefix=BASE + "/child")
      parent.include_router(child, prefix=BASE + "/mount")

      @literal.get("/route")
      def literal_route():
          return {}

      @constant.get("/route")
      def constant_route():
          return {}

      @defaulted.get("/route")
      def defaulted_route():
          return {}

      @tail.get("/route")
      def tail_route():
          return {}

      @unread.get("/route")
      def unread_route():
          return {}

      @variable.get("/variable")
      def variable_route():
          return {}

      @leading_runtime.get("/leading")
      def leading_runtime_route():
          return {}

      @env.get("/env")
      def env_route():
          return {}

      @call.get("/call")
      def call_route():
          return {}

      @include_unread.get("/include-unread")
      def include_unread_route():
          return {}

      @parent.get("/route")
      def parent_route():
          return {}

      @child.get("/route")
      def child_route():
          return {}

      @app.get("/health")
      def health():
          return {}

      app.include_router(literal)
      app.include_router(constant)
      app.include_router(defaulted)
      app.include_router(tail)
      app.include_router(unread)
      app.include_router(variable)
      app.include_router(leading_runtime)
      app.include_router(env)
      app.include_router(call)
      app.include_router(include_unread, prefix=os.getenv("INCLUDE_PREFIX"))
      app.include_router(parent)
      app.include_router(outer, prefix=BASE + "/mount")
      PY

    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(root)])
    options["nolog"] = YAML::Any.new(true)
    runner = NoirRunner.new(options)
    CodeLocator.instance.clear_all
    runner.detect
    runner.analyze

    by_url = runner.endpoints.to_h { |endpoint| {endpoint.url, endpoint} }
    by_url["/v1/route"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_HEURISTIC})
    by_url["/route"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/f-v1/fstring"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED, "registration" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/variable"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/leading"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/env"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/call"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/include-unread"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_UNRESOLVED})
    by_url["/parent/mount/child/route"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_HEURISTIC})
    by_url["/mount/outer/nested/external/route"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_HEURISTIC})
    by_url["/api/v1/route"].resolution.should eq({"prefix" => Endpoint::RESOLUTION_HEURISTIC})
    ["/literal/route", "/constant/route", "/parent/route", "/health"].each do |url|
      by_url[url].resolution.should be_nil
    end
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(root) if root && Dir.exists?(root)
  end
end
