require "../../../spec_helper"
require "../../../../src/detector/detectors/python/*"

describe "Detect Python http.server" do
  options = create_test_options
  instance = Detector::Python::HttpServer.new options

  it "detects from http.server import" do
    instance.detect("server.py", "from http.server import BaseHTTPRequestHandler, HTTPServer").should be_true
  end

  it "detects import http.server" do
    instance.detect("h.py", "import http.server\nserver = http.server.HTTPServer(('', 8080), Handler)").should be_true
  end

  it "detects by BaseHTTPRequestHandler class token" do
    instance.detect("handler.py", "class MyHandler(BaseHTTPRequestHandler):\n    def do_GET(self): pass").should be_true
  end

  it "detects by SimpleHTTPRequestHandler" do
    instance.detect("static.py", "from http.server import SimpleHTTPRequestHandler").should be_true
  end

  it "does not detect in non-.py" do
    instance.detect("requirements.txt", "http.server").should be_false
  end

  it "does not fire without signal" do
    instance.detect("other.py", "print('hello')").should be_false
  end
end
