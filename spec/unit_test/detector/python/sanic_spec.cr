require "../../../../src/detector/detectors/*"

describe "Detect Python Sanic" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Python::Sanic.new options

  it "detect_sanic - app.py" do
    instance.detect("app.py", "from sanic import Sanic").should eq(true)
  end
end