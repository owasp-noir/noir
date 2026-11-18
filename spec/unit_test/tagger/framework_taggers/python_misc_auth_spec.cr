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
end
