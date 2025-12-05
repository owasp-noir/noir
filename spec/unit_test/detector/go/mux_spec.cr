require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"

describe "Detect Go Mux" do
  options = create_test_options
  instance = Detector::Go::Mux.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gorilla/mux").should eq(true)
  end
end
