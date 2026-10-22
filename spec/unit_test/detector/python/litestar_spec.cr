require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Litestar" do
  options = create_test_options
  instance = Detector::Python::Litestar.new options

  it "from litestar import" do
    instance.detect("app.py", "from litestar import Litestar, get").should be_true
  end

  it "import litestar" do
    instance.detect("app.py", "import litestar").should be_true
  end

  it "non-litestar file" do
    instance.detect("app.py", "from fastapi import FastAPI").should be_false
  end

  it "non-python extension" do
    instance.detect("app.txt", "from litestar import Litestar").should be_false
  end
end
