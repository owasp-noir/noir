require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python aiohttp" do
  options = create_test_options
  instance = Detector::Python::Aiohttp.new options

  it "detect_aiohttp - app.py (from import)" do
    instance.detect("app.py", "from aiohttp import web").should be_true
  end

  it "detect_aiohttp - app.py (import)" do
    instance.detect("app.py", "import aiohttp").should be_true
  end

  it "detect_aiohttp - non-python file" do
    instance.detect("app.js", "from aiohttp import web").should be_false
  end

  it "detect_aiohttp - unrelated python file" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end
end
