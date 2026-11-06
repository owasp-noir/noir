require "../../func_spec.cr"

# Review cases for Ktor mount placement: each fixture is scanned alone and
# every endpoint's URL and guardedness is pinned.
private def ktor_mount_case(name : String) : Hash(String, Bool)
  CodeLocator.instance.clear_all
  options = ConfigInitializer.new.default_options
  options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/kotlin/ktor_mount_cases/#{name}/")])
  options["ai_context"] = YAML::Any.new(true)
  options["nolog"] = YAML::Any.new(true)

  app = NoirRunner.new(options)
  app.detect
  app.analyze
  app.endpoints.to_h do |endpoint|
    {"#{endpoint.method} #{endpoint.url}", endpoint.ai_context.try { |context| !context.guards.empty? } || false}
  end
end

describe "Ktor mount placement cases", tags: "functional" do
  it "guards what authenticate mounts, keeps siblings open, survives cycles" do
    ktor_mount_case("a").should eq({
      "GET /a/inline"  => true,
      "GET /api/stats" => true,
      "GET /api/hello" => false,
      # Mounted both open and behind authenticate at one prefix: open.
      "GET /mixed/shared" => false,
      "GET /opt"          => false,
      # cycA <-> cycB call each other: on a cycle, each keeps its own URL.
      "GET /ca"          => false,
      "GET /cb"          => false,
      "GET /outer/inner" => true,
    })
  end

  it "ignores foreign receivers and reads Optional strategies" do
    result = ktor_mount_case("b")
    # `svc.users()` outside routing is no call site.
    result["GET /api/users"].should be_true
    result.has_key?("GET /users").should be_false
    # `this@routing.label()`: prefix unknown, the only site, so its own URL.
    result["GET /labelled"].should be_false
    result["GET /maybe"].should be_false
  end

  it "keeps a guarded placement when an unplaced call also exists, and every prefix" do
    result = ktor_mount_case("c")
    result["GET /secret"].should be_true
    (1..20).each { |n| result["GET /r#{n}"].should be_false }
    result.has_key?("GET /").should be_false
  end

  it "keeps a cross-module mount when the name lives in one module" do
    ktor_mount_case("d").should eq({
      "GET /lib/status"   => false,
      "GET /admin/status" => true,
    })
  end

  it "places by byte span, not line, and survives non-ASCII and string braces" do
    ktor_mount_case("h").should eq({
      "GET /p/a"     => false,
      "GET /p/n/lam" => false,
      "GET /q/b"     => true,
      "GET /한글/c"    => false,
      # Two functions, and an authenticate block, sharing one line.
      "GET /pd/d"  => false,
      "GET /pe/e"  => false,
      "GET /g1/f"  => true,
      "GET /g2/f2" => false,
    })
  end

  it "resolves dense call cycles in one pass" do
    # A 12-function full mesh and 60 functions with random calls: every
    # function is on a cycle, so each keeps its own URL, without walking
    # every path.
    mesh = ktor_mount_case("mesh12")
    mesh.keys.sort!.should eq((0...12).map { |n| "GET /x#{n}" }.sort!)
    ktor_mount_case("rg60").size.should eq(60)
  end

  it "treats strategy = AuthenticationStrategy.Optional as optional in-file" do
    ktor_mount_case("g").should eq({"GET /m" => false})
  end
end
