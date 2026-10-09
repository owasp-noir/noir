require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/utils/http_symbols"
require "../../../src/analyzer/analyzers/rust/poem"
require "../../../src/analyzer/analyzers/rust/tide"

private def routes_of(analyzer : Analyzer, source : String) : Array(String)
  dir = File.tempname("rust_nest")
  Dir.mkdir_p(dir)
  file = File.join(dir, "main.rs")
  File.write(file, source)
  analyzer.analyze_file(file).map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  FileUtils.rm_rf(dir) if dir
end

describe "Rust nested route prefixes" do
  options = create_test_options

  it "applies poem .nest prefixes to inline and same-file fn routes" do
    routes_of(Analyzer::Rust::Poem.new(options), <<-RUST).should eq([
      fn main() {
          let app = Route::new()
              .at("/root", get(h))
              .nest("/api", Route::new().at("/users", get(h)))
              .nest("/v1", Route::new().nest("/inner", Route::new().at("/deep", get(h))).at("/flat", get(h)))
              .nest("/admin", admin())
              .nest_no_strip("/static", Route::new().at("/static/x", get(h)));
      }

      fn admin() -> Route {
          Route::new().at("/panel", get(h))
      }
      RUST
      "GET /admin/panel", "GET /api/users", "GET /root", "GET /static/x", "GET /v1/flat", "GET /v1/inner/deep",
    ])
  end

  it "composes tide .at() with route variables and chained .at() calls" do
    routes_of(Analyzer::Rust::Tide.new(options), <<-RUST).should eq([
      fn main() {
          let mut app = tide::new();
          let mut api = app.at("/api");
          api.at("/c").get(h);
          let mut v2 = api.at("/v2");
          v2.at("/e").post(h);
          app.at("/a").at("/b").get(h);
          app.at("/top").get(h);
          let ok = items.iter().all(|x| x > 0);
      }
      RUST
      "GET /a/b", "GET /api/c", "GET /top", "POST /api/v2/e",
    ])
  end

  it "fans tide .all() out to every method" do
    routes_of(Analyzer::Rust::Tide.new(options), <<-RUST).should eq(ANY_ROUTE_HTTP_METHODS.map { |m| "#{m} /any" }.sort!)
      fn main() {
          let mut app = tide::new();
          app.at("/any").all(h);
      }
      RUST
  end
end
