require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "KtorAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/kotlin/ktor_auth"
  app_path = "#{fixture_base}/src/Application.kt"

  # Application.kt line reference:
  # 10:     get("/public") {
  # 14:     authenticate("auth-jwt") {
  # 15:       get("/profile") {
  # 20:       post("/api/data") {
  # 25:     authenticate("auth-session") {
  # 26:       route("/admin") {
  # 27:         get("/dashboard") {
  # 33:     get("/health") {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects authenticate block wrapping route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ktor_auth")
    endpoint.tags[0].description.should contain("authenticate")
  end

  it "detects principal access in handler" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "does not tag public routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag health route outside authenticate block" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 33))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects authenticate block with nested route() block" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(app_path, 27))
    details.technology = "kotlin_ktor"
    endpoint = Endpoint.new("/admin/dashboard", "GET", [] of Param, details)

    tagger = KtorAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("ktor_auth")
    endpoint.tags[0].description.should contain("auth-session")
  end

  # --- negative cases: a route that nothing protects must never be tagged ---

  it "does not read the next route's handler when this one closes on its own line" do
    tmpdir = File.tempname("ktor_adjacent")
    Dir.mkdir_p(tmpdir)
    kt = File.join(tmpdir, "App.kt")
    File.write(kt, [
      "import io.ktor.server.routing.*",
      "",
      "fun Application.configureRouting() {",
      "    routing {",
      "        get(\"/public\") { call.respondText(\"public\") }",
      "        get(\"/me\") { val principal = call.principal<JWTPrincipal>() }",
      "    }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    public_details = Details.new(PathInfo.new(kt, 5))
    public_details.technology = "kotlin_ktor"
    public_endpoint = Endpoint.new("/public", "GET", [] of Param, public_details)

    me_details = Details.new(PathInfo.new(kt, 6))
    me_details.technology = "kotlin_ktor"
    me_endpoint = Endpoint.new("/me", "GET", [] of Param, me_details)

    KtorAuthTagger.new(noir_options).perform([public_endpoint, me_endpoint])

    public_endpoint.tags.empty?.should be_true
    # The one-line handler is now read as its own statement, so the route that
    # really does extract a principal keeps its tag.
    me_endpoint.tags.empty?.should be_false

    FileUtils.rm_rf(tmpdir)
  end

  it "keeps a nested authenticate block off sibling routes and other files" do
    tmpdir = File.tempname("ktor_scope")
    Dir.mkdir_p(tmpdir)

    secure = File.join(tmpdir, "Secure.kt")
    File.write(secure, [
      "import io.ktor.server.routing.*",             # 1
      "",                                            # 2
      "fun Application.secureRouting() {",           # 3
      "    routing {",                               # 4
      "        route(\"/api\") {",                   # 5
      "            route(\"/v1\") {",                # 6
      "                get(\"/a\") {",               # 7
      "                    call.respondText(\"a\")", # 8
      "                }",                           # 9
      "                authenticate(\"jwt\") {",     # 10
      "                    get(\"/b\") {",           # 11
      "                        call.respondText(\"b\")",
      "                    }",
      "                }",
      "            }",
      "        }",
      "    }",
      "}",
    ].join("\n"))

    public_kt = File.join(tmpdir, "Public.kt")
    File.write(public_kt, [
      "import io.ktor.server.routing.*",
      "",
      "fun Application.publicRouting() {",
      "    routing {",
      "        get(\"/api/public\") {",
      "            call.respondText(\"public\")",
      "        }",
      "    }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    locator = CodeLocator.instance
    Dir.glob("#{tmpdir}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    a_details = Details.new(PathInfo.new(secure, 7))
    a_details.technology = "kotlin_ktor"
    a_endpoint = Endpoint.new("/api/v1/a", "GET", [] of Param, a_details)

    b_details = Details.new(PathInfo.new(secure, 11))
    b_details.technology = "kotlin_ktor"
    b_endpoint = Endpoint.new("/api/v1/b", "GET", [] of Param, b_details)

    public_details = Details.new(PathInfo.new(public_kt, 5))
    public_details.technology = "kotlin_ktor"
    public_endpoint = Endpoint.new("/api/public", "GET", [] of Param, public_details)

    KtorAuthTagger.new(noir_options).perform([a_endpoint, b_endpoint, public_endpoint])

    # `/a` sits in the same route("/v1") block but outside authenticate {}.
    a_endpoint.tags.empty?.should be_true
    # Another file entirely, and not even under the block's prefix.
    public_endpoint.tags.empty?.should be_true
    # The one route the block really wraps.
    b_endpoint.tags.empty?.should be_false
    b_endpoint.tags[0].description.should contain("jwt")

    FileUtils.rm_rf(tmpdir)
  end
end
