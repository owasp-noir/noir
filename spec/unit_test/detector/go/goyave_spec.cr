require "../../../spec_helper"
require "../../../../src/detector/detectors/go/goyave"

describe "Detect Go Goyave" do
  options = create_test_options
  instance = Detector::Go::Goyave.new options

  it "go.mod" do
    instance.detect("go.mod", "goyave.dev/goyave").should be_true
  end
end
