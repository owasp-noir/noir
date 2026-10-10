require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python FastHTML" do
  options = create_test_options
  instance = Detector::Python::FastHTML.new options

  it "from fasthtml.common import *" do
    instance.detect("main.py", "from fasthtml.common import *\napp, rt = fast_app()").should be_true
  end

  it "from fasthtml import FastHTML" do
    instance.detect("app.py", "from fasthtml import FastHTML").should be_true
  end

  it "import fasthtml" do
    instance.detect("app.py", "import fasthtml").should be_true
  end

  it "mention without import" do
    instance.detect("app.py", "# ported from fasthtml\nfrom starlette.applications import Starlette").should be_false
  end

  it "non-python extension" do
    instance.detect("main.txt", "from fasthtml.common import *").should be_false
  end
end
