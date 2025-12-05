require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Flask" do
  options = create_test_options
  instance = Detector::Python::Flask.new options

  it "detect_flask - app.py" do
    instance.detect("app.py", "from flask import Flask").should eq(true)
  end
end
