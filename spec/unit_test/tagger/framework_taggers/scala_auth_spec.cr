require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "ScalaAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/scala/akka_auth", __DIR__)
  routes_path = "#{fixture_base}/Routes.scala"
  health_path = "#{fixture_base}/HealthRoutes.scala"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Akka HTTP authenticateBasic" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Routes.scala line 10: get { complete("Secure content") }
    details = Details.new(PathInfo.new(routes_path, 10))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/secure", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("scala_auth")
    endpoint.tags[0].description.should contain("authenticateBasic")
  end

  it "detects Akka HTTP authenticateOAuth2" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Routes.scala line 21: get { complete("OAuth resource") }
    details = Details.new(PathInfo.new(routes_path, 21))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/oauth-resource", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticateOAuth2")
  end

  it "detects Akka HTTP authorize directive" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # Routes.scala line 32: get { complete("Admin settings") }
    details = Details.new(PathInfo.new(routes_path, 32))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/api/admin/settings", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authorize")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    # HealthRoutes.scala line 11: get { complete("ok") }
    details = Details.new(PathInfo.new(health_path, 11))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not take a sibling object's balanced authorize block as enclosing" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    # Routes.scala line 43 sits in HealthRoutes, right after AdminRoutes'
    # `authorize(hasAdminRole) { … }` closes.
    details = Details.new(PathInfo.new(routes_path, 43))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/public/health", "GET", [] of Param, details)

    ScalaAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "reads a directive that opens on the line closing a sibling route" do
    tmpdir = File.tempname("akka_tilde")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "Routes.scala")
    File.write(file, [
      "val route =",
      "  path(\"a\") { get { complete(\"a\") } } ~ authenticateBasic(\"realm\", auth) { user =>",
      "    path(\"b\") {",
      "      get {",
      "        complete(\"b\")",
      "      }",
      "    }",
      "  }",
    ].join("\n"))

    details = Details.new(PathInfo.new(file, 4))
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/b", "GET", [] of Param, details)
    ScalaAuthTagger.new(create_test_options).perform([endpoint])

    endpoint.tags.map(&.description).should eq(["Protected by Akka HTTP authenticateBasic"])
    FileUtils.rm_rf(tmpdir)
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "scala_akka"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects Play Silhouette SecuredAction (regression for phantom-segment regex)" do
    noir_options = create_test_options
    tmpdir = File.tempname("scala_silhouette")
    Dir.mkdir_p(tmpdir)
    ctrl = File.join(tmpdir, "Controller.scala")
    File.write(ctrl, [
      "class HomeController @Inject() (silhouette: Silhouette[DefaultEnv]) {",
      "  def index = silhouette.SecuredAction { implicit request =>",
      "    Ok(\"secret\")",
      "  }",
      "}",
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(ctrl, 2))
    details.technology = "scala_play"
    endpoint = Endpoint.new("/", "GET", [] of Param, details)

    tagger = ScalaAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("Silhouette")

    FileUtils.rm_rf(tmpdir)
  end

  it "bounds a Scalatra route's check to its own block" do
    noir_options = create_test_options
    tmpdir = File.tempname("scalatra_block")
    Dir.mkdir_p(tmpdir)
    servlet = File.join(tmpdir, "MyServlet.scala")
    File.write(servlet, [
      "class MyServlet extends ScalatraServlet with AuthenticationSupport {", # 1
      "  get(\"/\") {",                                                       # 2
      "    \"hello\"",                                                        # 3
      "  }",                                                                  # 4
      "  get(\"/me\") {",                                                     # 5
      "    if (!isAuthenticated) halt(401)",                                  # 6
      "    \"me\"",                                                           # 7
      "  }",                                                                  # 8
      "  get(\"/about\") {",                                                  # 9
      "    \"about\"",                                                        # 10
      "  }",                                                                  # 11
      "}",                                                                    # 12
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {2 => "/", 5 => "/me", 9 => "/about"}.map do |line, url|
      details = Details.new(PathInfo.new(servlet, line))
      details.technology = "scala_scalatra"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    ScalaAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.map(&.tags.size).should eq([0, 1, 0])
    endpoints[1].tags[0].description.should contain("isAuthenticated")
  end

  it "reads a Play routes row's guard from its controller action" do
    noir_options = create_test_options
    tmpdir = File.tempname("scala_play_handler_guard")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "routes")
    File.write(routes, [
      "DELETE /inbox/:username controllers.Msg.convoDelete(username: String)",
      "GET    /inbox           controllers.Msg.list",
      "GET    /about           controllers.Msg.about",
    ].join("\n"))
    ctrl = File.join(tmpdir, "Msg.scala")
    File.write(ctrl, [
      "class Msg @Inject() (silhouette: Silhouette[DefaultEnv]) {",        # 1
      "  def convoDelete(username: String) = silhouette.SecuredAction {",  # 2
      "    implicit request => Ok(username)",                              # 3
      "  }",                                                               # 4
      "  def list =",                                                      # 5
      "    silhouette.SecuredAction { implicit request => Ok(\"list\") }", # 6
      "  def about = Action { Ok(\"about\") }",                            # 7
      "}",                                                                 # 8
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = [{1, "Msg.convoDelete", 2}, {2, "Msg.list", 5}, {3, "Msg.about", 7}].map do |routes_line, name, def_line|
      details = Details.new(PathInfo.new(routes, routes_line))
      details.technology = "scala_play"
      endpoint = Endpoint.new("/", "GET", [] of Param, details)
      endpoint.handler = Handler.new(name, ctrl, def_line)
      endpoint
    end
    ScalaAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints.map(&.tags.size).should eq([1, 1, 0])
    endpoints[0].tags[0].description.should eq("Protected by Play Silhouette SecuredAction")
    endpoints[1].tags[0].description.should eq("Protected by Play Silhouette SecuredAction")
  end

  it "returns correct target_techs" do
    ScalaAuthTagger.target_techs.should contain("scala_play")
    ScalaAuthTagger.target_techs.should contain("scala_akka")
    ScalaAuthTagger.target_techs.should contain("scala_scalatra")
    ScalaAuthTagger.target_techs.should contain("java_play")
  end
end
