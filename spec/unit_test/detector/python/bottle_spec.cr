require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Bottle" do
  options = create_test_options
  instance = Detector::Python::Bottle.new options

  it "from import" do
    instance.detect("app.py", "from bottle import route, run").should be_true
  end

  it "bare import" do
    instance.detect("app.py", "import bottle").should be_true
  end

  it "does not match a similarly named module" do
    instance.detect("app.py", "import bottleneck").should be_false
  end

  it "does not match non-python file" do
    instance.detect("requirements.txt", "from bottle import route").should be_false
  end
end
