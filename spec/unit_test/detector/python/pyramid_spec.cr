require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Pyramid" do
  options = create_test_options
  instance = Detector::Python::Pyramid.new options

  it "detect_pyramid - app.py (from pyramid.config import Configurator)" do
    instance.detect("app.py", "from pyramid.config import Configurator").should be_true
  end

  it "detect_pyramid - app.py (from pyramid.view import view_config)" do
    instance.detect("app.py", "from pyramid.view import view_config").should be_true
  end

  it "detect_pyramid - app.py (import pyramid)" do
    instance.detect("app.py", "import pyramid").should be_true
  end

  it "detect_pyramid - negative (no pyramid)" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end

  it "detect_pyramid - non-py file" do
    instance.detect("app.txt", "from pyramid.config import Configurator").should be_false
  end
end
