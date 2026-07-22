require "../../spec_helper"
require "../../../src/miniparsers/js_http_route_extractor"

describe Noir::JSHttpRouteExtractor do
  describe ".source_file?" do
    it "identifies JS/TS source files" do
      Noir::JSHttpRouteExtractor.source_file?("server.js").should be_true
      Noir::JSHttpRouteExtractor.source_file?("server.ts").should be_true
      Noir::JSHttpRouteExtractor.source_file?("README.md").should be_false
    end
  end

  describe ".extract" do
    it "extracts endpoints from node:http createServer" do
      code = <<-JS
      const http = require('http');
      const server = http.createServer((req, res) => {
        if (req.url === '/api/users' && req.method === 'GET') {
          res.end('users');
        } else if (req.url === '/api/posts' && req.method === 'POST') {
          res.end('posts');
        }
      });
      JS

      endpoints = Noir::JSHttpRouteExtractor.extract("app.js", code)
      endpoints.size.should eq(2)
      endpoints.any? { |e| e.url == "/api/users" && e.method == "GET" }.should be_true
      endpoints.any? { |e| e.url == "/api/posts" && e.method == "POST" }.should be_true
    end
  end
end
