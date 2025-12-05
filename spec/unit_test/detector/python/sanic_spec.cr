require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Sanic" do
  options = create_test_options
  instance = Detector::Python::Sanic.new options

  it "detect_sanic - app.py" do
    instance.detect("app.py", "from sanic import Sanic").should eq(true)
  end
end
