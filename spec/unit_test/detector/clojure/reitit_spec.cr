require "../../../spec_helper"
require "../../../../src/detector/detectors/clojure/*"

describe "Detect Clojure Reitit" do
  options = create_test_options
  instance = Detector::Clojure::Reitit.new options

  it "project.clj with metosin/reitit dependency" do
    instance.detect("project.clj", "(defproject demo \"0.1.0\" :dependencies [[metosin/reitit \"0.7.2\"]])").should be_true
  end

  it "core.clj with reitit.ring require" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [reitit.ring :as ring]))").should be_true
  end

  it "core.clj with reitit.core require" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [reitit.core]))").should be_true
  end

  it "non-clojure file with reitit token" do
    instance.detect("demo.txt", "reitit.ring").should be_false
  end

  it "unrelated clojure file" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [compojure.core]))").should be_false
  end
end
