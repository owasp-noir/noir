require "../../spec_helper"
require "../../../src/miniparsers/clojure_scanner"

describe Noir::ClojureScanner do
  describe "test_path?" do
    it "gates test trees, benchmark trees and foo_test files" do
      Noir::ClojureScanner.test_path?("/test/foo.clj").should be_true
      Noir::ClojureScanner.test_path?("/test/cljc/reitit/core_test.cljc").should be_true
      Noir::ClojureScanner.test_path?("/perf-test/x.clj").should be_true
      Noir::ClojureScanner.test_path?("/src/a_test.clj").should be_true
      Noir::ClojureScanner.test_path?("/sub/module/test/app/x.clj").should be_true
      Noir::ClojureScanner.test_path?("/Test/App/X_Test.clj").should be_true
    end

    it "keeps production sources, matching whole `test` segments only" do
      Noir::ClojureScanner.test_path?("/src/latest/a.clj").should be_false
      Noir::ClojureScanner.test_path?("/src/contest/a.clj").should be_false
      Noir::ClojureScanner.test_path?("/src/app/routes.clj").should be_false
      Noir::ClojureScanner.test_path?("/src/app/attest.clj").should be_false
      Noir::ClojureScanner.test_path?("/examples/ring/src/example/server.clj").should be_false
    end
  end
end
