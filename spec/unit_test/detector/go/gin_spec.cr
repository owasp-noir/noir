require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Gin" do
  options = create_test_options
  instance = Detector::Go::Gin.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should eq(true)
  end
end
