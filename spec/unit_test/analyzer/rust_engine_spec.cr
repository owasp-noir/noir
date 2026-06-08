require "../../spec_helper"
require "../../../src/analyzer/engines/rust_engine"

class RustEngineSpecHarness < Analyzer::Rust::RustEngine
  def analyze_file(path : String) : Array(Endpoint)
    [] of Endpoint
  end

  def function_body(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
    extract_rust_function_body(lines, start_index)
  end
end

describe Analyzer::Rust::RustEngine do
  describe ".test_path?" do
    it "skips Cargo test modules named tests.rs" do
      Analyzer::Rust::RustEngine.test_path?("src/apps/todo/tests.rs").should be_true
    end
  end

  it "does not attach declaration-only function signatures to the next body" do
    lines = [
      "trait Api {",
      "  fn declared();",
      "}",
      "async fn real_handler() {",
      "  RealService::run();",
      "}",
    ]

    harness = RustEngineSpecHarness.new(create_test_options)
    harness.function_body(lines, 1).should be_nil

    real_body = harness.function_body(lines, 3)
    real_body.should_not be_nil
    if real_body
      body, start_line = real_body
      start_line.should eq(5)
      body.should contain("RealService::run")
    end
  end

  describe ".collect_cfg_test_regions" do
    it "treats braces inside a raw string as opaque so the region spans the whole block" do
      source = <<-RUST
        fn real() {
            Router::with_path("/real").get(real_handler);
        }

        #[cfg(test)]
        mod tests {
            #[test]
            fn renders() {
                let raw = r#"{ "openapi": { "paths": {} } }"#;
                Router::with_path("/test-only").get(test_handler);
            }
        }
        RUST

      regions = Analyzer::Rust::RustEngine.collect_cfg_test_regions(source)
      regions.size.should eq(1)
      start_byte, end_byte = regions[0]

      # The test-only route is registered *after* the brace-laden raw
      # string; without raw-string handling the region would close early
      # at a `}` inside the JSON and leak that route as an endpoint.
      test_route = source.byte_index("/test-only").not_nil!
      (test_route >= start_byte && test_route < end_byte).should be_true

      # The production route above the block stays outside the region.
      real_route = source.byte_index("/real").not_nil!
      (real_route >= start_byte && real_route < end_byte).should be_false
    end

    it "still closes a cfg(test) block that contains no raw strings" do
      source = <<-RUST
        #[cfg(test)]
        mod tests {
            fn t() { let x = 1; }
        }

        fn after() {}
        RUST

      regions = Analyzer::Rust::RustEngine.collect_cfg_test_regions(source)
      regions.size.should eq(1)
      _start_byte, end_byte = regions[0]
      after_byte = source.byte_index("fn after").not_nil!
      (after_byte >= end_byte).should be_true
    end
  end
end
