require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Falcon" do
  options = create_test_options
  instance = Detector::Python::Falcon.new options

  it "detect_falcon - app.py with import falcon" do
    instance.detect("app.py", "import falcon").should be_true
  end

  it "detect_falcon - app.py with from falcon import App" do
    instance.detect("app.py", "from falcon import App").should be_true
  end

  it "detect_falcon - app.py with from falcon.asgi import App" do
    instance.detect("app.py", "from falcon.asgi import App").should be_true
  end

  it "detect_falcon - app.py with import falcon.asgi" do
    instance.detect("app.py", "import falcon.asgi").should be_true
  end

  it "detect_falcon - app.py without falcon" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end

  it "detect_falcon - non-python file" do
    instance.detect("app.js", "import falcon").should be_false
  end
end
