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
end
