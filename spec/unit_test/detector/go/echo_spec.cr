require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Echo" do
  options = create_test_options
  instance = Detector::Go::Echo.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/labstack/echo").should eq(true)
  end
end
