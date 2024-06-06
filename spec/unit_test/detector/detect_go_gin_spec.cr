require "../../../src/detector/detectors/*"

describe "Detect Go Gin" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = DetectorGoGin.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should eq(true)
  end
end
