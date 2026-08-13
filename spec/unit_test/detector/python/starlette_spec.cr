require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Starlette" do
  options = create_test_options
  instance = Detector::Python::Starlette.new options

  it "from starlette import" do
    instance.detect("app.py", "from starlette.applications import Starlette").should be_true
  end

  it "import starlette" do
    instance.detect("app.py", "import starlette").should be_true
  end

  it "non-starlette file" do
    instance.detect("app.py", "from fastapi import FastAPI").should be_false
  end

  it "non-python extension" do
    instance.detect("app.txt", "from starlette import").should be_false
  end
end
