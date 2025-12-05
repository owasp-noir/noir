require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Chi" do
  options = create_test_options
  instance = Detector::Go::Chi.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/go-chi/chi").should eq(true)
  end
end
