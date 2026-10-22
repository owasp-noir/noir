require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Robyn" do
  options = create_test_options
  instance = Detector::Python::Robyn.new options

  it "from import" do
    instance.detect("app.py", "from robyn import Robyn").should be_true
  end

  it "bare import" do
    instance.detect("app.py", "import robyn").should be_true
  end

  it "does not match requirements.txt" do
    instance.detect("requirements.txt", "robyn==0.60.0").should be_false
  end

  it "does not match unrelated python source" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end
end
