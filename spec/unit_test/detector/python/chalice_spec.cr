require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Chalice" do
  options = create_test_options
  instance = Detector::Python::Chalice.new options

  it "from chalice import Chalice" do
    instance.detect("app.py", "from chalice import Chalice\napp = Chalice(app_name='x')").should be_true
  end

  it "blueprint module" do
    instance.detect("chalicelib/api.py", "from chalice import Blueprint").should be_true
  end

  it "import chalice" do
    instance.detect("app.py", "import chalice").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# ported from chalice import style\nimport flask").should be_false
  end

  it "non-python extension" do
    instance.detect("app.txt", "from chalice import Chalice").should be_false
  end
end
