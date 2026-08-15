require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python CherryPy" do
  options = create_test_options
  instance = Detector::Python::CherryPy.new options

  it "detect_cherrypy - app.py (import cherrypy)" do
    instance.detect("app.py", "import cherrypy").should be_true
  end

  it "detect_cherrypy - app.py (from cherrypy import expose)" do
    instance.detect("app.py", "from cherrypy import expose").should be_true
  end

  it "detect_cherrypy - app.py (import cherrypy, sys)" do
    instance.detect("app.py", "import cherrypy, sys").should be_true
  end

  it "detect_cherrypy - negative (no cherrypy)" do
    instance.detect("app.py", "from flask import Flask").should be_false
  end

  it "detect_cherrypy - non-py file" do
    instance.detect("app.txt", "import cherrypy").should be_false
  end
end
