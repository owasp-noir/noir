require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python Masonite" do
  options = create_test_options
  instance = Detector::Python::Masonite.new options

  it "detect_masonite - routes/web.py (from masonite.routes import Route)" do
    instance.detect("routes/web.py", "from masonite.routes import Route").should be_true
  end

  it "detect_masonite - app/controllers/WelcomeController.py (from masonite.controllers import Controller)" do
    instance.detect("app/controllers/WelcomeController.py", "from masonite.controllers import Controller").should be_true
  end

  it "detect_masonite - Kernel.py (import masonite.foundation)" do
    instance.detect("Kernel.py", "import masonite.foundation").should be_true
  end

  it "detect_masonite - negative (no masonite)" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end

  it "detect_masonite - non-py file" do
    instance.detect("routes/web.txt", "from masonite.routes import Route").should be_false
  end
end
