require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "RustAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/rust/actix_auth"
  main_path = "#{fixture_base}/src/main.rs"

  # main.rs line reference:
  #  6: #[get("/health")]
  #  7: async fn health() -> HttpResponse {
  # 12: #[get("/public")]
  # 13: async fn public_page() -> HttpResponse {
  # 18: #[get("/profile")]
  # 19: async fn profile(auth: BearerAuth) -> HttpResponse {
  # 24: #[guard = "AdminGuard"]
  # 25: #[get("/admin/users")]
  # 26: async fn admin_users() -> HttpResponse {
  # 31: #[post("/api/posts")]
  # 32: async fn create_post(user: AuthUser, body: web::Json<PostData>) -> HttpResponse {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects BearerAuth extractor in function signature" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 18))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("rust_auth")
    endpoint.tags[0].description.should contain("BearerAuth")
  end

  it "detects #[guard] attribute" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 25))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/admin/users", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("guard")
  end

  it "detects AuthUser guard type in function signature" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 31))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/api/posts", "POST", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AuthUser")
  end

  it "does not tag public endpoints" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 6))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag public_page endpoint" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 12))
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = RustAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
