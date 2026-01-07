require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Fiber" do
  options = create_test_options
  instance = Detector::Go::Fiber.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gofiber/fiber").should be_true
  end
end
