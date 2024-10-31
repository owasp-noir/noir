require "../../../../src/detector/detectors/*"

describe "Detect Python Flask" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Python::Flask.new options

  it "detect_flask - app.py" do
    instance.detect("app.py", "from flask import Flask").should eq(true)
  end
end
