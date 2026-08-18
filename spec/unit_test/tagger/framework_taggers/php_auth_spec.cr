require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "PhpAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/php/laravel_auth"
  controller_path = "#{fixture_base}/app/Http/Controllers/PostController.php"
  public_path = "#{fixture_base}/app/Http/Controllers/PublicController.php"

  # PostController.php line reference:
  # 10:     $this->middleware('auth');
  # 14:   public function index()
  # 19:   public function store(Request $request)
  # 21:     $this->authorize('create', Post::class);

  it "detects $this->middleware('auth') in constructor" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("php_auth")
    endpoint.tags[0].description.should contain("auth")
  end

  it "detects $this->authorize in action body" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 19))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end

  it "does not attribute the next route's middleware to the route above it" do
    tmpdir = File.tempname("php_adjacent_routes")
    Dir.mkdir_p(tmpdir)
    routes = File.join(tmpdir, "web.php")
    File.write(routes, [
      "<?php",
      "",
      "Route::get('/public', function () { return 'public'; });",
      "Route::get('/me', function () { return 'me'; })->middleware('auth');",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    public_details = Details.new(PathInfo.new(routes, 3))
    public_details.technology = "php_laravel"
    public_endpoint = Endpoint.new("/public", "GET", [] of Param, public_details)

    me_details = Details.new(PathInfo.new(routes, 4))
    me_details.technology = "php_laravel"
    me_endpoint = Endpoint.new("/me", "GET", [] of Param, me_details)

    PhpAuthTagger.new(noir_options).perform([public_endpoint, me_endpoint])

    public_endpoint.tags.empty?.should be_true
    me_endpoint.tags.empty?.should be_false
    me_endpoint.tags[0].description.should contain("Laravel auth middleware")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not sweep the next method's auth check into this action's body" do
    tmpdir = File.tempname("php_method_body")
    Dir.mkdir_p(tmpdir)
    controller = File.join(tmpdir, "ReportController.php")
    File.write(controller, [
      "<?php",                                     # 1
      "",                                          # 2
      "class ReportController extends Controller", # 3
      "{",                                         # 4
      "    public function publicIndex()",         # 5
      "    {",                                     # 6
      "        return response()->json(['ok' => true]);",
      "    }",                        # 8
      "",                             # 9
      "    public function secret()", # 10
      "    {",                        # 11
      "        $this->authorize('view', Report::class);",
      "    }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    public_details = Details.new(PathInfo.new(controller, 5))
    public_details.technology = "php_laravel"
    public_endpoint = Endpoint.new("/reports/public", "GET", [] of Param, public_details)

    secret_details = Details.new(PathInfo.new(controller, 10))
    secret_details.technology = "php_laravel"
    secret_endpoint = Endpoint.new("/reports/secret", "GET", [] of Param, secret_details)

    PhpAuthTagger.new(noir_options).perform([public_endpoint, secret_endpoint])

    public_endpoint.tags.empty?.should be_true
    secret_endpoint.tags.empty?.should be_false
    secret_endpoint.tags[0].description.should contain("Policy authorization")

    FileUtils.rm_rf(tmpdir)
  end

  it "does not tag public controller" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(public_path, 8))
    details.technology = "php_laravel"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end

# Light coverage for newly added PHP targets (Slim, Yii, CodeIgniter)
describe "PhpAuthTagger (expanded targets)" do
  slim_base = "#{__DIR__}/../../../functional_test/fixtures/php/slim"
  slim_path = "#{slim_base}/index.php"

  it "runs without error on php_slim technology" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(slim_base)

    # Line 28 in slim fixture has X-Auth-Token header access (manual auth pattern)
    details = Details.new(PathInfo.new(slim_path, 28))
    details.technology = "php_slim"
    endpoint = Endpoint.new("/users/{id}", "GET", [] of Param, details)

    tagger = PhpAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    # We don't assert a tag (fixture has manual header read, not strong declarative auth),
    # but the tagger must not crash and must accept the tech.
    true.should be_true
  end

  it "runs without error on php_yii and php_codeigniter technologies" do
    noir_options = create_test_options
    # Reuse slim dir as base (no real Yii/CI files needed for smoke test)
    noir_options["base"] = YAML::Any.new(slim_base)

    ["php_yii", "php_codeigniter"].each do |tech|
      details = Details.new(PathInfo.new(slim_path, 10))
      details.technology = tech
      endpoint = Endpoint.new("/test", "GET", [] of Param, details)

      tagger = PhpAuthTagger.new(noir_options)
      # Should not raise
      tagger.perform([endpoint])
    end

    true.should be_true
  end

  describe "session user guard (regression for never-match session pattern)" do
    it "detects a guarded $_SESSION['user'] access in the handler body" do
      tmpdir = File.tempname("php_session_guard")
      Dir.mkdir_p(tmpdir)
      file = File.join(tmpdir, "handler.php")
      File.write(file, [
        "<?php",
        "function dashboard() {",
        "    if (!isset($_SESSION['user_id'])) { header('Location: /login'); exit; }",
        "    echo 'secret';",
        "}",
      ].join("\n"))

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(file, 2))
      details.technology = "php_pure"
      endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

      PhpAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags.empty?.should be_false
      endpoint.tags[0].description.should contain("session user guard")

      FileUtils.rm_rf(tmpdir)
    end

    it "does not tag a bare session_start() bootstrap" do
      tmpdir = File.tempname("php_session_bare")
      Dir.mkdir_p(tmpdir)
      file = File.join(tmpdir, "public.php")
      File.write(file, [
        "<?php",
        "function home() {",
        "    session_start();",
        "    echo 'welcome';",
        "}",
      ].join("\n"))

      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(file, 2))
      details.technology = "php_pure"
      endpoint = Endpoint.new("/", "GET", [] of Param, details)

      PhpAuthTagger.new(noir_options).perform([endpoint])
      endpoint.tags.empty?.should be_true

      FileUtils.rm_rf(tmpdir)
    end
  end
end
