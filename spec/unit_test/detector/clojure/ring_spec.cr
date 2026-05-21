require "../../../spec_helper"
require "../../../../src/detector/detectors/clojure/*"

describe "Detect Clojure Ring" do
  options = create_test_options
  instance = Detector::Clojure::Ring.new options

  it "project.clj with ring/ring-core dependency" do
    instance.detect("project.clj", "(defproject demo \"0.1.0\" :dependencies [[ring/ring-core \"1.12.2\"]])").should be_true
  end

  it "core.clj with ring.adapter.jetty require" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [ring.adapter.jetty :as jetty]))").should be_true
  end

  it "core.clj with direct request-map dispatch" do
    instance.detect("src/demo/core.clj", "(defn handler [req] (case [(:request-method req) (:uri req)]))").should be_true
  end

  it "project.clj without any ring dependency" do
    instance.detect("project.clj", "(defproject demo \"0.1.0\" :dependencies [[compojure \"1.7.1\"]])").should be_false
  end

  it "non-clojure file containing the word ring" do
    instance.detect("demo.txt", "ring.adapter.jetty").should be_false
  end
end
