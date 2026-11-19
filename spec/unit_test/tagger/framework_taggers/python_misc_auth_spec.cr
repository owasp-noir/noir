require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "PythonMiscAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/python/tornado_auth", __DIR__)
  app_path = "#{fixture_base}/app.py"

  # app.py line reference:
  #  4: class BaseHandler(tornado.web.RequestHandler):
  #  5:     def get_current_user(self):
  #  8: class MainHandler(BaseHandler):
  #  9:     @tornado.web.authenticated
  # 10:     def get(self):
  # 13: class ProfileHandler(BaseHandler):
  # 14:     @authenticated
  # 15:     def get(self):
  # 18: class PublicHandler(tornado.web.RequestHandler):
  # 19:     def get(self):

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Tornado @tornado.web.authenticated decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/main", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("python_misc_auth")
    endpoint.tags[0].description.should contain("authenticated")
  end

  it "detects @authenticated shorthand decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticated")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag on a bare current_user mention above the handler (false-positive regression)" do
    tmpdir = File.tempname("tornado_fp")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "app.py")
    File.write(file, [
      "class PublicHandler(tornado.web.RequestHandler):",
      "    # current_user is set elsewhere from a token",
      "    def get(self):",
      "        self.write('public')",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(file, 3))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    PythonMiscAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.empty?.should be_true

    FileUtils.rm_rf(tmpdir)
  end

  describe "Tornado route tables" do
    # The route sits in a handler list; the handler class lives in another module.
    write_tornado_app = ->(handlers : String) do
      tmpdir = File.tempname("tornado_table")
      Dir.mkdir_p(tmpdir)
      urls = File.join(tmpdir, "urls.py")
      api = File.join(tmpdir, "api.py")
      File.write(urls, "from api import ItemHandler, LoginHandler\n\nhandlers = [\n    (r\"/api/items\", ItemHandler),\n    (r\"/login\", LoginHandler),\n]\n")
      File.write(api, handlers)
      {urls, api}
    end
    tag = ->(urls : String, route_line : Int32, handler : Handler) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(File.dirname(urls))
      details = Details.new(PathInfo.new(urls, route_line))
      details.technology = "python_tornado"
      endpoint = Endpoint.new("/x", "GET", [] of Param, details)
      endpoint.handler = handler
      PythonMiscAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags
    end

    it "reads the decorators on the handler method the route dispatches to" do
      urls, api = write_tornado_app.call([
        "from tornado import web",
        "",
        "class ItemHandler(web.RequestHandler):",
        "    @web.authenticated",
        "    def get(self):",
        "        self.write('items')",
      ].join("\n"))
      tags = tag.call(urls, 4, Handler.new("ItemHandler.get", api, 5))
      FileUtils.rm_rf(File.dirname(urls))
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should contain("authenticated")
    end

    it "does not guard a handler for a get_current_user override alone" do
      # Tornado's get_current_user only computes current_user;
      # @tornado.web.authenticated is what turns an anonymous caller away.
      _, api = write_tornado_app.call([
        "import tornado.web",
        "",
        "class LoginHandler(tornado.web.RequestHandler):",
        "    def get(self):",
        "        self.redirect('/')",
        "",
        "class ItemHandler(tornado.web.RequestHandler):",
        "    def get_current_user(self):",
        "        return self.get_secure_cookie('user')",
        "",
        "    def get(self):",
        "        self.write('items')",
        "",
        "def main():",
        "    app = tornado.web.Application([",
        "        ('/login', LoginHandler),",
        "        ('/', ItemHandler),",
        "    ])",
      ].join("\n"))
      login = tag.call(api, 16, Handler.new("LoginHandler.get", api, 4))
      item = tag.call(api, 17, Handler.new("ItemHandler.get", api, 11))
      FileUtils.rm_rf(File.dirname(api))
      login.should be_empty
      item.should be_empty
    end
  end

  it "reads a Tornado decorator past a wrapped decorator or a comment line" do
    tmpdir = File.tempname("tornado_wrapped")
    Dir.mkdir_p(tmpdir)
    api = File.join(tmpdir, "api.py")
    File.write(api, [
      "import tornado.web",
      "",
      "class ItemHandler(tornado.web.RequestHandler):",
      "    @tornado.web.authenticated",
      "    # cached per user",
      "    @cache(",
      "        ttl=60,",
      "    )",
      "    def get(self):",
      "        self.write('items')",
    ].join("\n"))
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(api, 1))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/items", "GET", [] of Param, details)
    endpoint.handler = Handler.new("ItemHandler.get", api, 9)
    PythonMiscAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)
    endpoint.tags.map(&.name).should eq(["auth"])
  end

  it "returns correct target_techs" do
    PythonMiscAuthTagger.target_techs.should contain("python_sanic")
    PythonMiscAuthTagger.target_techs.should contain("python_tornado")
  end

  describe "Litestar guards" do
    litestar_base = File.expand_path("../../../functional_test/fixtures/python/litestar_guards", __DIR__)
    litestar_app = "#{litestar_base}/app/main.py"

    # app/main.py: 13 `@get(..., guards=[requires_team_membership])`,
    # 22 `@get("/stats")` in a Controller with `guards = [...]`,
    # 28 `@get(..., name="oauth:github:authorize")` with no guard.
    tag_at = ->(line : Int32) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(litestar_base)
      details = Details.new(PathInfo.new(litestar_app, line))
      details.technology = "python_litestar"
      endpoint = Endpoint.new("/x", "GET", [] of Param, details)
      PythonMiscAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags
    end

    it "reads a handler's guards= argument" do
      tags = tag_at.call(13)
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should contain("requires_team_membership")
    end

    it "reads a Controller's guards attribute" do
      tag_at.call(22).map(&.name).should eq(["auth"])
    end

    it "does not guard a route without guards" do
      tag_at.call(28).should be_empty
    end
  end

  describe "Litestar auth backends" do
    tmpdir = File.tempname("litestar_backend")
    guards = File.join(tmpdir, "app", "guards.py")
    routes = File.join(tmpdir, "app", "routes.py")
    sibling = File.join(tmpdir, "other", "routes.py")
    lines = [
      "from litestar import Controller, Litestar, get, post",
      "from app.guards import auth",
      "",
      "class AccountController(Controller):",
      "    @get(\"/api/me\")",
      "    async def me(self) -> dict: ...",
      "",
      "    @get(\"/health\")",
      "    async def health(self) -> dict: ...",
      "",
      "    @post(\"/api/access/signup\", exclude_from_auth=True)",
      "    async def signup(self) -> dict: ...",
      "",
      "app = Litestar(route_handlers=[AccountController], on_app_init=[auth.on_app_init])",
    ]

    before_all do
      Dir.mkdir_p(File.dirname(guards))
      Dir.mkdir_p(File.dirname(sibling))
      File.write(File.join(tmpdir, "pyproject.toml"), "[project]\nname = \"app\"\n")
      File.write(File.join(tmpdir, "other", "pyproject.toml"), "[project]\nname = \"other\"\n")
      File.write(guards, [
        "from litestar.security.jwt import OAuth2PasswordBearerAuth",
        "",
        "auth = OAuth2PasswordBearerAuth[User](",
        "    retrieve_user_handler=current_user_from_token,",
        "    token_secret=\"secret\",",
        "    token_url=\"/api/access/login\",",
        "    exclude=[\"/health\", \"/api/access/login\", \"^/schema\"],",
        ")",
      ].join("\n"))
      File.write(routes, lines.join("\n"))
      File.write(sibling, "from litestar import get\n\n@get(\"/api/me\")\nasync def me() -> dict: ...\n")
    end

    after_all { FileUtils.rm_rf(tmpdir) }

    tag = ->(file : String, line : Int32, url : String, method : String) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      [guards, routes, sibling].each { |path| CodeLocator.instance.register_path(path) }
      details = Details.new(PathInfo.new(file, line))
      details.technology = "python_litestar"
      endpoint = Endpoint.new(url, method, [] of Param, details)
      PythonMiscAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags
    end

    it "guards a route the app's auth backend does not exclude" do
      tags = tag.call(routes, 5, "/api/me", "GET")
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should contain("OAuth2PasswordBearerAuth")
    end

    it "leaves a path matching an exclude pattern open" do
      tag.call(routes, 8, "/health", "GET").should be_empty
    end

    it "leaves a route marked exclude_from_auth open" do
      tag.call(routes, 11, "/api/access/signup", "POST").should be_empty
    end

    it "leaves OPTIONS and HEAD open, as the backend's default exclude_http_methods does" do
      tag.call(routes, 5, "/api/me", "HEAD").should be_empty
    end

    it "does not apply one project's backend to a sibling project" do
      tag.call(sibling, 3, "/api/me", "GET").should be_empty
    end
  end

  describe "Litestar auth backend scope and settings" do
    # No manifest anywhere: each service directory is its own app.
    tmpdir = File.tempname("litestar_scope")
    svc_a = File.join(tmpdir, "svc_a", "app.py")
    svc_b = File.join(tmpdir, "svc_b", "app.py")
    svc_c = File.join(tmpdir, "svc_c", "app.py")

    before_all do
      [svc_a, svc_b, svc_c].each { |path| Dir.mkdir_p(File.dirname(path)) }
      File.write(svc_a, [
        "from litestar import Controller, Litestar, get",
        "from litestar.security.jwt import JWTAuth",
        "",
        "jwt_auth = JWTAuth[dict](",
        "    retrieve_user_handler=retrieve_user,",
        "    token_secret=\"x\",",
        "    exclude=[\"/static/[a-z]+\", \"/health\"],",
        ")",
        "",
        "@get(\"/a/me\")",
        "async def me() -> dict: ...",
        "",
        "@get(\"/health\")",
        "async def health() -> dict: ...",
        "",
        "class PublicController(Controller):",
        "    path = \"/pub\"",
        "    opt = {\"exclude_from_auth\": True}",
        "",
        "    @get(\"/info\")",
        "    async def info(self) -> dict: ...",
        "",
        "app = Litestar(route_handlers=[me, health, PublicController], on_app_init=[jwt_auth.on_app_init])",
      ].join("\n"))
      File.write(svc_b, "from litestar import Litestar, get\n\n@get(\"/b/public\")\nasync def public() -> dict: ...\n\napp = Litestar(route_handlers=[public])\n")
      File.write(svc_c, [
        "from litestar import Litestar, route",
        "from litestar.security.jwt import JWTAuth",
        "",
        "jwt_auth = JWTAuth[dict](retrieve_user_handler=retrieve_user, token_secret=\"x\", exclude_http_methods=None)",
        "",
        "@route(\"/c/cors\", http_method=[\"OPTIONS\", \"HEAD\"])",
        "async def cors() -> None: ...",
        "",
        "app = Litestar(route_handlers=[cors], middleware=[jwt_auth.middleware])",
      ].join("\n"))
    end

    after_all { FileUtils.rm_rf(tmpdir) }

    tag = ->(file : String, line : Int32, url : String, method : String) do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      [svc_a, svc_b, svc_c].each { |path| CodeLocator.instance.register_path(path) }
      details = Details.new(PathInfo.new(file, line))
      details.technology = "python_litestar"
      endpoint = Endpoint.new(url, method, [] of Param, details)
      PythonMiscAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags
    end

    it "guards only the app the backend is wired into" do
      tag.call(svc_a, 10, "/a/me", "GET").map(&.name).should eq(["auth"])
      tag.call(svc_b, 3, "/b/public", "GET").should be_empty
    end

    it "reads an exclude list whose patterns hold brackets" do
      tag.call(svc_a, 13, "/health", "GET").should be_empty
    end

    it "leaves a Controller's routes open when its opt excludes them" do
      tag.call(svc_a, 20, "/pub/info", "GET").should be_empty
    end

    it "excludes only OPTIONS when exclude_http_methods is None" do
      tag.call(svc_c, 6, "/c/cors", "OPTIONS").should be_empty
      tag.call(svc_c, 6, "/c/cors", "HEAD").map(&.name).should eq(["auth"])
    end
  end
end
