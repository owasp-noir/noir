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

  it "does not fire on a `python -m http.server` mention in prose" do
    src = <<-PY
      """Utilities.

      To preview the generated docs locally run:

          python -m http.server 8000
      """

      def add(a, b):
          return a + b
      PY
    instance.detect("util.py", src).should be_false
  end

  it "does not claim Tornado's HTTPServer" do
    src = <<-PY
      import tornado.web
      from tornado.httpserver import HTTPServer

      server = HTTPServer(tornado.web.Application([]))
      PY
    instance.detect("main.py", src).should be_false
  end

  it "detects a comma-list import" do
    instance.detect("s.py", "import socketserver, http.server\n").should be_true
  end

  it "detects a first-line import in a UTF-8-BOM file" do
    instance.detect("s.py", "\uFEFFimport http.server\n").should be_true
  end

  it "detects a mixin-first handler subclass" do
    src = "class Handler(ThreadingMixIn, BaseHTTPRequestHandler):\n    pass"
    instance.detect("handler.py", src).should be_true
  end

  it "detects `from http import server`" do
    instance.detect("s.py", "from http import server\nserver.HTTPServer(('', 0), H)").should be_true
  end
end
