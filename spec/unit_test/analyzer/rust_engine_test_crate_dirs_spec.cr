require "../../spec_helper"
require "../../../src/analyzer/engines/rust_engine"

describe Analyzer::Rust::RustEngine do
  describe ".test_path? test crate directories" do
    it "skips workspace test crates named after the tests convention" do
      [
        "/rwf-tests/src/main.rs",
        "/tests-fuzz/utils/kafka_wal_helper.rs",
        "/packages/playwright-tests/fullstack/src/main.rs",
        "/examples/suspense_tests/src/app.rs",
        "/crates/e2e_test/src/a.rs",
        "/e2e/src/a.rs",
        "/crates/integration-tests-common/src/a.rs",
      ].each { |path| Analyzer::Rust::RustEngine.test_path?(path).should be_true }
    end

    it "keeps names that only resemble the convention" do
      [
        "/contests/src/a.rs",
        "/src/latest/a.rs",
        "/crates/test-app/src/main.rs",
        "/crates/test_only/src/lib.rs",
        "/crates/attests/src/lib.rs",
        "/src/tests_helper.rs",
      ].each { |path| Analyzer::Rust::RustEngine.test_path?(path).should be_false }
    end
  end
end
