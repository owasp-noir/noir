require "../../../../src/detector/detectors/go/*"

describe "Detect Go BeegoEcho" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Go::Beego.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/beego/beego").should eq(true)
  end
end
