require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/utils/http_symbols"
require "../../../src/analyzer/analyzers/rust/axum"
require "../../../src/analyzer/analyzers/rust/actix_web"
require "../../../src/analyzer/analyzers/rust/poem"
require "../../../src/analyzer/analyzers/rust/tide"
require "../../../src/analyzer/analyzers/rust/loco"
require "../../../src/analyzer/analyzers/rust/salvo"

# A chained call node starts at the chain's first token, so every route of a
# multi-line builder chain used to report the `Router::new()` line.
private def chain_lines(analyzer : Analyzer, source : String) : Array(Tuple(String, String, Int32?))
  dir = File.tempname("rust_chain_lines")
  Dir.mkdir_p(dir)
  file = File.join(dir, "main.rs")
  File.write(file, source)
  endpoints = analyzer.analyze_file(file)
  endpoints.map { |e| {e.method, e.url, e.details.code_paths.first?.try(&.line)} }.sort_by!(&.[2].to_s)
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "Rust builder-chain route lines" do
  options = create_test_options

  it "axum" do
    chain_lines(Analyzer::Rust::Axum.new(options), <<-RUST).should eq([{"GET", "/one", 3}, {"POST", "/two", 4}])
      fn app() -> Router {
          Router::new()
              .route("/one", get(h))
              .route("/two", post(h))
      }
      RUST
  end

  it "actix-web" do
    chain_lines(Analyzer::Rust::ActixWeb.new(options), <<-RUST).should eq([{"GET", "/one", 3}, {"POST", "/two", 4}])
      fn main() {
          App::new()
              .route("/one", web::get().to(h))
              .route("/two", web::post().to(h));
      }
      RUST
  end

  it "poem" do
    chain_lines(Analyzer::Rust::Poem.new(options), <<-RUST).should eq([{"GET", "/one", 3}, {"POST", "/two", 4}])
      fn main() {
          let app = Route::new()
              .at("/one", get(h))
              .at("/two", post(h));
      }
      RUST
  end

  it "tide" do
    chain_lines(Analyzer::Rust::Tide.new(options), <<-RUST).should eq([{"GET", "/one", 3}, {"POST", "/one", 4}])
      fn main() {
          app.at("/one")
              .get(h)
              .post(h);
      }
      RUST
  end

  it "loco" do
    chain_lines(Analyzer::Rust::Loco.new(options), <<-RUST).should eq([{"GET", "/api/one", 5}, {"POST", "/api/two", 6}])
      use loco_rs::prelude::*;
      pub fn routes() -> Routes {
          Routes::new()
              .prefix("/api")
              .add("/one", get(h))
              .add("/two", post(h))
      }
      RUST
  end

  it "salvo" do
    chain_lines(Analyzer::Rust::Salvo.new(options), <<-RUST).should eq([{"GET", "/items", 3}, {"POST", "/items", 4}])
      fn route() -> Router {
          Router::with_path("items")
              .get(h)
              .post(h)
      }
      RUST
  end
end
