require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Every Rust analyzer is handed every `.rs` file in the scan, and the route
# DSLs are close enough to collide: axum's `.route("/foo", get(handler))` and
# actix's glob-imported `.route("/foo", get().to(handler))` are the same tree.
# The Cargo manifest is what tells them apart.
private def scan_tree(root : String, techs : String? = nil) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  options["techs"] = YAML::Any.new(techs) if techs
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.clear("file_map")
end

private def tech_sources(endpoints : Array(Endpoint), technology : String) : Array(String)
  endpoints.compact_map do |endpoint|
    next unless endpoint.details.technology == technology
    endpoint.details.code_paths.first?.try(&.path)
  end.uniq!
end

private def write_axum_crate(dir : String)
  FileUtils.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "Cargo.toml"), <<-TOML)
    [package]
    name = "gateway"

    [dependencies]
    axum = "0.7"
    tokio = { version = "1", features = ["full"] }
    TOML
  File.write(File.join(dir, "src", "main.rs"), <<-RUST)
    use axum::{routing::{get, post}, Router};

    #[tokio::main]
    async fn main() {
        let app = Router::new()
            .route("/gateway/health", get(handler))
            .route("/gateway/submit", post(handler));
        axum::serve(listener, app).await.unwrap();
    }
    RUST
end

private def write_actix_crate(dir : String)
  FileUtils.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "Cargo.toml"), <<-TOML)
    [package]
    name = "billing"

    [dependencies]
    actix-web = "4.9"
    TOML
  File.write(File.join(dir, "src", "main.rs"), <<-RUST)
    use actix_web::{get, web, App, HttpServer, Responder};

    #[get("/billing/invoices")]
    async fn invoices() -> impl Responder { "ok" }

    #[actix_web::main]
    async fn main() -> std::io::Result<()> {
        HttpServer::new(|| App::new().service(invoices)).bind(("127.0.0.1", 8080))?.run().await
    }
    RUST
end

describe "Rust crate scoping" do
  it "keeps actix-web off an axum crate and the other way round" do
    root = File.tempname("noir-rust-crate-scope")

    begin
      write_axum_crate(File.join(root, "gateway"))
      write_actix_crate(File.join(root, "billing"))

      endpoints = scan_tree(root)

      axum_sources = tech_sources(endpoints, "rust_axum")
      axum_sources.any?(&.includes?("/gateway/src/main.rs")).should be_true
      axum_sources.any?(&.includes?("/billing/")).should be_false

      actix_sources = tech_sources(endpoints, "rust_actix_web")
      actix_sources.any?(&.includes?("/billing/src/main.rs")).should be_true
      # Pre-fix actix claimed every axum `.route(path, get(handler))` in the
      # scan, because a bare `get(...)` argument is also actix's glob-imported
      # route constructor.
      actix_sources.any?(&.includes?("/gateway/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "falls back to scanning everything when no manifest declares the crate" do
    # A source tree checked out without its Cargo.toml (or a `-t` forced tech)
    # must behave exactly as it did before the gate existed.
    root = File.tempname("noir-rust-no-manifest")

    begin
      write_axum_crate(root)
      File.delete(File.join(root, "Cargo.toml"))

      endpoints = scan_tree(root, techs: "rust_axum")
      endpoints.map(&.url).should contain("/gateway/health")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
