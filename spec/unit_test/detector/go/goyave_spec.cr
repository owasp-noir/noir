require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Goyave" do
  options = create_test_options
  instance = Detector::Go::Goyave.new options

  it "go.mod with goyave dependency" do
    instance.detect("go.mod", "require goyave.dev/goyave/v5 v5.0.0").should be_true
  end

  it "go.mod without goyave dependency" do
    instance.detect("go.mod", "require github.com/gin-gonic/gin v1.9.0").should be_false
  end

  it "ignores a .go import (go.mod only)" do
    instance.detect("main.go", "import \"goyave.dev/goyave/v5\"").should be_false
  end

  it "ignores unrelated file" do
    instance.detect("README.md", "goyave.dev/goyave").should be_false
  end
end
