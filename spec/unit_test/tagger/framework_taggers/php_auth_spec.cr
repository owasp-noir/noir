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
