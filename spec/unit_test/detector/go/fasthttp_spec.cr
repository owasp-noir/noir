require "spec"
require "../../../../src/config_initializer"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Fasthttp" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Go::Fasthttp.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/valyala/fasthttp").should eq(true)
  end

  it "should not detect when fiber is present" do
    instance.detect("go.mod", "github.com/valyala/fasthttp\ngithub.com/gofiber/fiber").should eq(false)
  end

  it "should not detect other frameworks" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should eq(false)
  end

  it "should not detect non-go.mod files" do
    instance.detect("main.go", "github.com/valyala/fasthttp").should eq(false)
  end
end