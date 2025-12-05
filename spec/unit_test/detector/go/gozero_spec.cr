require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go go-zero" do
  options = create_test_options
  instance = Detector::Go::GoZero.new options

  it "go.mod with go-zero dependency" do
    instance.detect("go.mod", "github.com/zeromicro/go-zero").should eq(true)
  end

  it "go.mod without go-zero dependency" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should eq(false)
  end

  it "non go.mod file" do
    instance.detect("main.go", "github.com/zeromicro/go-zero").should eq(false)
  end
end
