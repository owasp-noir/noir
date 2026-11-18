require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Fixture line references
#
# actix/src/main.rs
#    8: async fn health()        -> GET /health
#   13: async fn list_users()    -> GET /api/users
#   19: async fn admin_import()  -> POST /admin/import   (under /admin scope)
#   App::new() wraps: Cors::permissive(), DefaultHeaders (X-Frame-Options,
#   Content-Security-Policy), JsonConfig.limit; the /admin scope wraps
#   Governor::new(). A #[cfg(test)] module also wraps Cors::permissive().
#
# axum/src/main.rs
#   app() layers: CorsLayer::very_permissive(), GovernorLayer,
#   SetResponseHeaderLayer(STRICT_TRANSPORT_SECURITY),
#   DefaultBodyLimit::disable()  (all app-wide, prefix "/").
#
# loco/config/development.yaml
#   server.middlewares: limit_payload (enable), cors (allow_origins "*"),
#   secure_headers (enable), compression (enable: false).
#
# test_only/src/main.rs
#    8: async fn widget() -> GET /widget; all middleware is #[cfg(test)].

private def load_fixture(base : String) : Hash(String, YAML::Any)
  CodeLocator.instance.clear_all
  options = create_test_options
  options["base"] = YAML::Any.new(base)

  locator = CodeLocator.instance
  Dir.glob("#{base}/**/*").each do |file|
    next if File.directory?(file)
    locator.register_path(file)
  end
  options
end

private def tag_named(endpoint : Endpoint, name : String) : Tag?
  endpoint.tags.find { |t| t.name == name }
end

private def build_endpoint(path : String, line : Int32, url : String, method : String, tech : String) : Endpoint
  details = Details.new(PathInfo.new(path, line))
  details.technology = tech
  Endpoint.new(url, method, [] of Param, details)
end

# `url => tags` from `RustSecurityTagger` over an inline axum project.
private def axum_security_tags(src : String, urls : Array(String)) : Hash(String, Array(String))
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("axum_security")
  main = File.join(tmpdir, "src", "main.rs")
  Dir.mkdir_p(File.dirname(main))
  File.write(main, src)
  CodeLocator.instance.register_path(main)
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  endpoints = urls.map { |url| build_endpoint(main, 1, url, "GET", "rust_axum") }
  RustSecurityTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.to_h { |e| {e.url, e.tags.map(&.name).sort!} }
end

describe "RustSecurityTagger" do
  it "does not read an imported protection type as an applied layer" do
    src = <<-RUST
      use axum::{
          extract::{DefaultBodyLimit, Path},
          routing::get,
          Router,
      };
      use tower_governor::GovernorLayer;

      pub fn routes() -> Router {
          Router::new().route("/items", get(list_items))
      }
      RUST
    axum_security_tags(src, ["/items"]).should eq({"/items" => [] of String})
  end

  it "applies an axum layer only to the routes registered before it" do
    src = <<-RUST
      use axum::{extract::DefaultBodyLimit, routing::{get, post}, Router};
      use tower_http::cors::CorsLayer;

      pub fn file_routes() -> Router {
          Router::new()
              .route("/files", get(list_files).post(upload_file))
              .layer(DefaultBodyLimit::max(64 * 1024 * 1024))
              .route("/files/new", get(new_file))
              .route("/avatar", post(set_avatar).layer(DefaultBodyLimit::max(1024)))
      }

      pub fn app() -> Router {
          Router::new().route("/health", get(health)).merge(file_routes())
      }

      pub async fn run(api: Router) {
          let app = api
              .layer(CorsLayer::permissive())
              .route("/metrics", get(metrics));
          serve(app).await;
      }
      RUST
    tags = axum_security_tags(src, ["/files", "/files/new", "/avatar", "/health", "/metrics", "/api/items"])
    tags.should eq({
      "/files"     => ["body-limit", "cors"],
      "/files/new" => ["cors"],
      "/avatar"    => ["body-limit", "cors"],
      "/health"    => ["cors"],
      "/metrics"   => [] of String,
      "/api/items" => ["cors"],
    })
  end

  fixtures = File.expand_path("../../../functional_test/fixtures/rust/rust_security", __DIR__)

  describe "target techs" do
    it "covers the major Rust web frameworks" do
      techs = RustSecurityTagger.target_techs
      techs.should contain("rust_actix_web")
      techs.should contain("rust_axum")
      techs.should contain("rust_loco")
    end
  end

  describe "actix-web (source middleware)" do
    actix_base = "#{fixtures}/actix"
    main_path = "#{actix_base}/src/main.rs"

    it "flags app-wide permissive CORS on every endpoint" do
      options = load_fixture(actix_base)
      endpoint = build_endpoint(main_path, 8, "/health", "GET", "rust_actix_web")
      RustSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "cors")
      tag.should_not be_nil
      tag.not_nil!.tagger.should eq("rust_security")
      tag.not_nil!.description.should contain("Permissive")
    end

    it "flags app-wide security headers and body limit" do
      options = load_fixture(actix_base)
      endpoint = build_endpoint(main_path, 13, "/api/users", "GET", "rust_actix_web")
      RustSecurityTagger.new(options).perform([endpoint])

      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "body-limit").should_not be_nil
    end

    it "scopes rate limiting to the /admin scope only" do
      options = load_fixture(actix_base)

      admin = build_endpoint(main_path, 19, "/admin/import", "POST", "rust_actix_web")
      RustSecurityTagger.new(options).perform([admin])
      tag_named(admin, "rate-limit").should_not be_nil

      health = build_endpoint(main_path, 8, "/health", "GET", "rust_actix_web")
      RustSecurityTagger.new(options).perform([health])
      tag_named(health, "rate-limit").should be_nil
    end
  end

  describe "axum / tower-http (source middleware)" do
    axum_base = "#{fixtures}/axum"
    main_path = "#{axum_base}/src/main.rs"

    it "flags very_permissive CORS as a risk" do
      options = load_fixture(axum_base)
      endpoint = build_endpoint(main_path, 8, "/health", "GET", "rust_axum")
      RustSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "cors")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("Permissive")
    end

    it "flags a disabled body limit as a risk" do
      options = load_fixture(axum_base)
      endpoint = build_endpoint(main_path, 12, "/upload", "POST", "rust_axum")
      RustSecurityTagger.new(options).perform([endpoint])

      tag = tag_named(endpoint, "body-limit")
      tag.should_not be_nil
      tag.not_nil!.description.should contain("disabled")
    end

    it "detects rate limiting and HSTS security header via tower layers" do
      options = load_fixture(axum_base)
      endpoint = build_endpoint(main_path, 8, "/health", "GET", "rust_axum")
      RustSecurityTagger.new(options).perform([endpoint])

      tag_named(endpoint, "rate-limit").should_not be_nil
      headers = tag_named(endpoint, "security-headers")
      headers.should_not be_nil
      headers.not_nil!.description.should contain("HSTS")
    end
  end

  describe "Loco (YAML config middleware)" do
    loco_base = "#{fixtures}/loco"

    it "maps limit_payload / cors / secure_headers onto every endpoint" do
      options = load_fixture(loco_base)
      # Loco controllers live elsewhere; the endpoint just needs a tech.
      details = Details.new
      details.technology = "rust_loco"
      endpoint = Endpoint.new("/api/notes", "GET", [] of Param, details)
      RustSecurityTagger.new(options).perform([endpoint])

      tag_named(endpoint, "body-limit").should_not be_nil
      tag_named(endpoint, "security-headers").should_not be_nil

      cors = tag_named(endpoint, "cors")
      cors.should_not be_nil
      cors.not_nil!.description.should contain("Permissive")
    end
  end

  describe "test-module isolation" do
    test_base = "#{fixtures}/test_only"
    main_path = "#{test_base}/src/main.rs"

    it "ignores middleware defined inside #[cfg(test)] modules" do
      options = load_fixture(test_base)
      endpoint = build_endpoint(main_path, 8, "/widget", "GET", "rust_actix_web")
      RustSecurityTagger.new(options).perform([endpoint])

      endpoint.tags.empty?.should be_true
    end
  end

  it "handles empty code_paths gracefully" do
    options = load_fixture("#{fixtures}/actix")
    details = Details.new
    details.technology = "rust_actix_web"
    endpoint = Endpoint.new("/unknown", "GET", [] of Param, details)

    RustSecurityTagger.new(options).perform([endpoint])
    # App-wide source middleware still applies even without code_paths,
    # because protections are pre-scanned from the file map, not the
    # endpoint's own path.
    endpoint.tags.empty?.should be_false
  end
end
