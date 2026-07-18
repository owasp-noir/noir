require "../../../spec_helper"
require "../../../../src/detector/detectors/r/*"

describe "Detect R Plumber" do
  options = create_test_options
  instance = Detector::R::Plumber.new options

  it "detects plumber library import" do
    content = <<-R
      library(plumber)
      library(ggplot2)
      R
    instance.detect("api.R", content).should be_true
  end

  it "detects plumber annotation comments" do
    content = <<-R
      #* @get /echo
      #* @param msg The message to echo
      function(msg = "") {
        msg
      }
      R
    instance.detect("api.R", content).should be_true
  end

  it "detects programmatic plumber routes" do
    content = <<-R
      pr() %>%
        pr_get("/hello", function() "Hello") %>%
        pr_run()
      R
    instance.detect("app.R", content).should be_true
  end

  it "does not detect plain R files" do
    content = <<-R
      print("Hello World")
      x <- 1:10
      mean(x)
      R
    instance.detect("script.R", content).should be_false
  end
end
