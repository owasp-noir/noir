require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Hertz" do
  options = create_test_options
  instance = Detector::Go::Hertz.new options

  it "go.mod with hertz dependency" do
    instance.detect("go.mod", "require github.com/cloudwego/hertz v0.9.0").should be_true
  end

  it "go.mod without hertz dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "detects a .go import (go.mod not yet tidied)" do
    instance.detect("main.go", "import \"github.com/cloudwego/hertz/pkg/app\"").should be_true
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "github.com/cloudwego/hertz").should be_false
  end
end
