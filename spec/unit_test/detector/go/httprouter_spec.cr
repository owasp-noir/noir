require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Httprouter" do
  options = create_test_options
  instance = Detector::Go::Httprouter.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/julienschmidt/httprouter").should be_true
  end
end
