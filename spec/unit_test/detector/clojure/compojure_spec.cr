require "../../../spec_helper"
require "../../../../src/detector/detectors/clojure/*"

describe "Detect Clojure Compojure" do
  options = create_test_options
  instance = Detector::Clojure::Compojure.new options

  it "project.clj with compojure dependency" do
    instance.detect("project.clj", "(defproject demo \"0.1.0\" :dependencies [[compojure \"1.7.1\"]])").should be_true
  end

  it "core.clj with compojure require" do
    instance.detect("src/demo/core.clj", "(ns demo.core (:require [compojure.core :refer [defroutes GET]]))").should be_true
  end

  it "non-clojure file with compojure token" do
    instance.detect("demo.txt", "compojure").should be_false
  end
end
