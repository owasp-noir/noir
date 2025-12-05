require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go BeegoEcho" do
  options = create_test_options
  instance = Detector::Go::Beego.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/beego/beego").should eq(true)
  end
end
