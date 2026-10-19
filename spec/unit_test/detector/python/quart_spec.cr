require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Quart" do
  options = create_test_options
  instance = Detector::Python::Quart.new options

  it "from import" do
    instance.detect("app.py", "from quart import Quart").should be_true
  end

  it "from submodule import" do
    instance.detect("app.py", "from quart.views import MethodView").should be_true
  end

  it "bare import" do
    instance.detect("app.py", "import quart").should be_true
  end

  it "does not match a similarly named module" do
    instance.detect("app.py", "import quartz").should be_false
  end

  it "does not match non-python file" do
    instance.detect("requirements.txt", "from quart import Quart").should be_false
  end
end
