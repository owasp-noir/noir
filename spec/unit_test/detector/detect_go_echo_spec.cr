require "../../../src/detector/detectors/*"

describe "Detect Go Echo" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorGoEcho.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/labstack/echo").should eq(true)
  end
end
