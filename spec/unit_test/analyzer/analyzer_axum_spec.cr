require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/rust/axum"

describe Analyzer::Rust::Axum do
  options = create_test_options

  it "detects basic routing::query routes" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::query, Router};

      async fn search_handler() {}

      fn app() -> Router {
          Router::new()
              .route("/search", query(search_handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/search")
    endpoints[0].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects chained MethodRouter with .query()" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{get, query}, Router};

      async fn list_handler() {}
      async fn query_handler() {}

      fn app() -> Router {
          Router::new()
              .route("/items", get(list_handler).query(query_handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)
    endpoints[0].url.should eq("/items")
    endpoints[0].method.should eq("GET")
    endpoints[1].url.should eq("/items")
    endpoints[1].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects query_service routes" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::query_service, Router};

      fn app() -> Router {
          Router::new()
              .route("/svc", query_service(my_svc))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/svc")
    endpoints[0].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects on(MethodFilter::QUERY, ...)" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{on, MethodFilter}, Router};

      async fn handler() {}

      fn app() -> Router {
          Router::new()
              .route("/filter-q", on(MethodFilter::QUERY, handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(1)
    endpoints[0].url.should eq("/filter-q")
    endpoints[0].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects on(MethodFilter::GET.or(MethodFilter::QUERY), ...)" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{on, MethodFilter}, Router};

      async fn handler() {}

      fn app() -> Router {
          Router::new()
              .route("/combo", on(MethodFilter::GET.or(MethodFilter::QUERY), handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)
    endpoints[0].url.should eq("/combo")
    endpoints[0].method.should eq("GET")
    endpoints[1].url.should eq("/combo")
    endpoints[1].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects on(MethodFilter::GET | MethodFilter::QUERY, ...)" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{on, MethodFilter}, Router};

      async fn handler() {}

      fn app() -> Router {
          Router::new()
              .route("/pipe-combo", on(MethodFilter::GET | MethodFilter::QUERY, handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(2)
    endpoints[0].url.should eq("/pipe-combo")
    endpoints[0].method.should eq("GET")
    endpoints[1].url.should eq("/pipe-combo")
    endpoints[1].method.should eq("QUERY")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects on(MethodFilter::all(), ...) and fans out" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{on, MethodFilter}, Router};

      async fn handler() {}

      fn app() -> Router {
          Router::new()
              .route("/all-methods", on(MethodFilter::all(), handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    endpoints.size.should eq(7)
    endpoints.map(&.method).sort!.should eq(%w[DELETE GET HEAD OPTIONS PATCH POST PUT].sort!)

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "propagates nest prefix to QUERY routes" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{get, on, query, MethodFilter}, Router};

      async fn handler() {}

      fn api_routes() -> Router {
          Router::new()
              .route("/search", query(handler))
              .route("/items", get(handler).query(handler))
              .route("/filter", on(MethodFilter::QUERY, handler))
      }

      fn app() -> Router {
          Router::new()
              .nest("/api/v1", api_routes())
              .nest("/scoped", Router::new().route("/direct-query", query(handler)))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    urls_and_methods = endpoints.map { |e| {e.url, e.method} }

    urls_and_methods.should contain({"/api/v1/search", "QUERY"})
    urls_and_methods.should contain({"/api/v1/items", "GET"})
    urls_and_methods.should contain({"/api/v1/items", "QUERY"})
    urls_and_methods.should contain({"/api/v1/filter", "QUERY"})
    urls_and_methods.should contain({"/scoped/direct-query", "QUERY"})

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects chained .on() and on_service()" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::{get, on, on_service, MethodFilter}, Router};

      async fn list_handler() {}
      async fn query_handler() {}

      fn app() -> Router {
          Router::new()
              .route("/items", get(list_handler).on(MethodFilter::QUERY, query_handler))
              .route("/svc", on_service(MethodFilter::QUERY, my_svc))
              .route("/multi", on(MethodFilter::GET.or(MethodFilter::POST).or(MethodFilter::QUERY), list_handler))
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    urls_and_methods = endpoints.map { |e| {e.url, e.method} }

    urls_and_methods.should contain({"/items", "GET"})
    urls_and_methods.should contain({"/items", "QUERY"})
    urls_and_methods.should contain({"/svc", "QUERY"})
    urls_and_methods.should contain({"/multi", "GET"})
    urls_and_methods.should contain({"/multi", "POST"})
    urls_and_methods.should contain({"/multi", "QUERY"})

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "detects custom route builders with query and unauthenticated_query" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      fn app() {
          RouteBuilder::new()
              .query("/custom-query", handler)
              .unauthenticated_query("/open-query", handler);
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    urls_and_methods = endpoints.map { |e| {e.url, e.method} }

    urls_and_methods.should contain({"/custom-query", "QUERY"})
    urls_and_methods.should contain({"/open-query", "QUERY"})

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end

  it "ignores QUERY routes inside #[cfg(test)] mod tests" do
    instance = Analyzer::Rust::Axum.new(options)
    temp_dir = File.tempname("axum_test")
    Dir.mkdir_p(temp_dir)
    temp_file = File.join(temp_dir, "test.rs")

    File.write(temp_file, <<-RUST)
      use axum::{routing::query, Router};

      async fn prod_handler() {}
      async fn test_handler() {}

      fn app() -> Router {
          Router::new()
              .route("/prod-query", query(prod_handler))
      }

      #[cfg(test)]
      mod tests {
          use super::*;

          fn test_app() -> Router {
              Router::new()
                  .route("/test-query", query(test_handler))
          }
      }
      RUST

    endpoints = instance.analyze_file(temp_file)
    urls = endpoints.map(&.url)

    urls.should contain("/prod-query")
    urls.should_not contain("/test-query")

    File.delete(temp_file)
    Dir.delete(temp_dir)
  end
end
