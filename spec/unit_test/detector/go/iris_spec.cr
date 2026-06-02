require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Iris" do
  options = create_test_options
  instance = Detector::Go::Iris.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/kataras/iris/v12").should be_true
  end

  # A `.go` file importing Iris detects too (sub-directory scans).
  it "go file importing iris" do
    instance.detect("main.go", "github.com/kataras/iris/v12").should be_true
  end

  it "go file without iris import" do
    instance.detect("main.go", "github.com/gin-gonic/gin").should be_false
  end
end
