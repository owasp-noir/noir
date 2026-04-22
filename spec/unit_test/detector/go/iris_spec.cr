require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Iris" do
  options = create_test_options
  instance = Detector::Go::Iris.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/kataras/iris/v12").should be_true
  end
end
