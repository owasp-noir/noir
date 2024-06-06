require "../../../src/detector/detectors/*"

describe "Detect Go Fiber" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorGoFiber.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gofiber/fiber").should eq(true)
  end
end
