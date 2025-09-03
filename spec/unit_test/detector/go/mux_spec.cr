require "../../../spec_helper"
require "../../../../src/detector/detectors/go/*"
require "../../../../src/config_initializer"

describe "Detect Go Mux" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Go::Mux.new options

  it "go.mod" do
    instance.detect("go.mod", "github.com/gorilla/mux").should eq(true)
  end
end