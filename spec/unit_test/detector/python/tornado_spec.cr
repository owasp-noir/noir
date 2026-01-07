require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Tornado" do
  options = create_test_options
  instance = Detector::Python::Tornado.new options

  it "detect_tornado - app.py with import tornado" do
    instance.detect("app.py", "import tornado").should be_true
  end

  it "detect_tornado - app.py with from tornado import web" do
    instance.detect("app.py", "from tornado import web").should be_true
  end

  it "detect_tornado - app.py with from tornado.web import Application" do
    instance.detect("app.py", "from tornado.web import Application").should be_true
  end

  it "detect_tornado - app.py without tornado" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end

  it "detect_tornado - non-python file" do
    instance.detect("app.js", "import tornado").should be_false
  end
end
