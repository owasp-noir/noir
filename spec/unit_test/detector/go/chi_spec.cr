require "../../../../src/detector/detectors/go/*"

describe "Detect Go Chi" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Go::Chi.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/go-chi/chi").should eq(true)
  end
end
