require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Fasthttp" do
  options = create_test_options
  instance = Detector::Go::Fasthttp.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/valyala/fasthttp").should be_true
  end

  it "should not detect when fiber is present" do
    instance.detect("go.mod", "github.com/valyala/fasthttp\ngithub.com/gofiber/fiber").should be_false
  end

  it "should not detect other frameworks" do
    instance.detect("go.mod", "github.com/gin-gonic/gin").should be_false
  end

  it "should not detect non-go.mod files" do
    instance.detect("main.go", "github.com/valyala/fasthttp").should be_false
  end
end
