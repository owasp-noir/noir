require "../../../src/detector/detectors/*"

describe "Detect Go BeegoEcho" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorGoBeego.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/beego/beego").should eq(true)
  end
end
