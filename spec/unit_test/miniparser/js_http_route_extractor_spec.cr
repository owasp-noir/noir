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

    it "extracts HTTP QUERY routes from if conditions with body params" do
      code = <<-JS
        const http = require('node:http');
        const server = http.createServer((req, res) => {
          if (req.method === 'QUERY' && req.url === '/api/items/search') {
            let body = '';
            req.on('data', chunk => { body += chunk; });
            req.on('end', () => {
              const { query, limit } = JSON.parse(body);
              res.end(JSON.stringify({ query, limit }));
            });
          }
        });
        JS

      endpoints = Noir::JSHttpRouteExtractor.extract("app.js", code)
      endpoints.size.should eq(1)
      ep = endpoints.first
      ep.url.should eq("/api/items/search")
      ep.method.should eq("QUERY")
      ep.params.map(&.name).should eq(["query", "limit"])
      ep.params.map(&.param_type).should eq(["json", "json"])
    end

    it "extracts HTTP QUERY routes from switch statements" do
      code = <<-JS
        const http = require('http');
        const server = http.createServer((req, res) => {
          const url = new URL(req.url, 'http://localhost');
          switch (req.method) {
            case 'QUERY':
              if (url.pathname === '/search') {
                const { filter } = JSON.parse('{}');
                res.end(filter);
              }
              break;
          }
        });
        JS

      endpoints = Noir::JSHttpRouteExtractor.extract("server.js", code)
      endpoints.size.should eq(1)
      ep = endpoints.first
      ep.url.should eq("/search")
      ep.method.should eq("QUERY")
      ep.params.map(&.name).should eq(["filter"])
      ep.params.map(&.param_type).should eq(["json"])
    end

    it "finds a named handler declared with a non-ASCII type annotation" do
      # The handler offset was computed as `match.begin(0) + match[0].bytesize`,
      # mixing a char index with a byte length. Any multi-byte character in
      # the declaration pushed the offset past the handler body and the
      # route disappeared entirely.
      code = <<-TS
        import { createServer } from 'node:http';

        const handler: 요청핸들러 = function (req, res) {
          if (req.url === '/api/status' && req.method === 'GET') {
            res.end('ok');
          }
        };

        createServer(handler).listen(3000);
        TS

      endpoints = Noir::JSHttpRouteExtractor.extract("server.ts", code)
      endpoints.map { |e| {e.method, e.url} }.should eq([{"GET", "/api/status"}])
    end
  end
end
