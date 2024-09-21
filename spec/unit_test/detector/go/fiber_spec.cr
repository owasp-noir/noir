require "../../../../src/detector/detectors/go/*"

describe "Detect Go Fiber" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Go::Fiber.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gofiber/fiber").should eq(true)
  end
end
