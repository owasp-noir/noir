require "../../../spec_helper"
require "../../../../src/detector/detectors/clojure/*"

describe "Detect Clojure Pedestal" do
  options = create_test_options
  instance = Detector::Clojure::Pedestal.new options

  it "project.clj with io.pedestal dependency" do
    instance.detect("project.clj", "(defproject demo \"0.1.0\" :dependencies [[io.pedestal/pedestal.service \"0.7.2\"]])").should be_true
  end

  it "deps.edn with pedestal route dependency" do
    instance.detect("deps.edn", "{:deps {io.pedestal/pedestal.route {:mvn/version \"0.8.1\"}}}").should be_true
  end

  it "core.clj with pedestal require" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [io.pedestal.http.route :as route]))").should be_true
  end

  it "non-clojure file with pedestal token" do
    instance.detect("demo.txt", "io.pedestal.http").should be_false
  end

  it "unrelated clojure file" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [compojure.core]))").should be_false
  end
end
