require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Tornado" do
  options = create_test_options
  instance = Detector::Python::Tornado.new options

  it "detect_tornado - app.py with import tornado" do
    instance.detect("app.py", "import tornado").should eq(true)
  end

  it "detect_tornado - app.py with from tornado import web" do
    instance.detect("app.py", "from tornado import web").should eq(true)
  end

  it "detect_tornado - app.py with from tornado.web import Application" do
    instance.detect("app.py", "from tornado.web import Application").should eq(true)
  end

  it "detect_tornado - app.py without tornado" do
    instance.detect("app.py", "from flask import Flask").should eq(false)
  end

  it "detect_tornado - non-python file" do
    instance.detect("app.js", "import tornado").should eq(false)
  end
end
