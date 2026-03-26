require "../../spec_helper"
require "../../../src/utils/utils"
require "../../../src/models/logger"
require "../../../src/miniparsers/js_route_extractor"

describe Noir::JSRouteExtractor do
  describe ".normalize_http_method" do
    it "normalizes DEL to DELETE" do
      Noir::JSRouteExtractor.normalize_http_method("DEL").should eq("DELETE")
    end

    it "keeps standard methods as-is" do
      Noir::JSRouteExtractor.normalize_http_method("GET").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("POST").should eq("POST")
      Noir::JSRouteExtractor.normalize_http_method("PUT").should eq("PUT")
      Noir::JSRouteExtractor.normalize_http_method("DELETE").should eq("DELETE")
      Noir::JSRouteExtractor.normalize_http_method("PATCH").should eq("PATCH")
      Noir::JSRouteExtractor.normalize_http_method("HEAD").should eq("HEAD")
    end

    it "keeps ALL as ALL" do
      Noir::JSRouteExtractor.normalize_http_method("ALL").should eq("ALL")
    end

    it "uppercases methods" do
      Noir::JSRouteExtractor.normalize_http_method("get").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("post").should eq("POST")
    end
  end

  describe ".extract_routes" do
    it "returns empty for non-existent file" do
      result = Noir::JSRouteExtractor.extract_routes("/nonexistent/file.js")
      result.should be_empty
    end

    it "extracts routes from Express app file" do
      fixture_path = "#{__DIR__}/../../functional_test/fixtures/javascript/express_auth/app.js"
      File.exists?(fixture_path).should be_true
      endpoints = Noir::JSRouteExtractor.extract_routes(fixture_path)

      endpoints.should_not be_empty
      endpoints.any? { |e| e.url == "/public" && e.method == "GET" }.should be_true
      endpoints.any? { |e| e.url == "/profile" && e.method == "GET" }.should be_true
      endpoints.any? { |e| e.url == "/api/data" && e.method == "POST" }.should be_true
      endpoints.any? { |e| e.url == "/dashboard" && e.method == "GET" }.should be_true
      endpoints.any? { |e| e.url == "/api/health" && e.method == "GET" }.should be_true
    end

    it "extracts routes from content string" do
      content = <<-JS
      const express = require('express');
      const app = express();
      app.get('/users', (req, res) => {
        const { name } = req.query;
        res.json([]);
      });
      app.post('/users', (req, res) => {
        const { username, email } = req.body;
        res.json({});
      });
      JS

      # Create a temporary file for testing
      tmp_path = "/tmp/noir_test_extractor_#{Random.new.rand(100000)}.js"
      File.write(tmp_path, content)
      begin
        endpoints = Noir::JSRouteExtractor.extract_routes(tmp_path, content)

        endpoints.any? { |e| e.url == "/users" && e.method == "GET" }.should be_true
        endpoints.any? { |e| e.url == "/users" && e.method == "POST" }.should be_true

        # Check body param extraction
        post_endpoint = endpoints.find { |e| e.url == "/users" && e.method == "POST" }
        post_endpoint.should_not be_nil
        post_endpoint = post_endpoint.not_nil!
        param_names = post_endpoint.params.map(&.name)
        param_names.should contain("username")
        param_names.should contain("email")

        # Check query param extraction
        get_endpoint = endpoints.find { |e| e.url == "/users" && e.method == "GET" }
        get_endpoint.should_not be_nil
        get_endpoint = get_endpoint.not_nil!
        param_names = get_endpoint.params.map(&.name)
        param_names.should contain("name")
      ensure
        File.delete(tmp_path) if File.exists?(tmp_path)
      end
    end
  end

  describe ".extract_static_paths" do
    it "extracts Express static paths with prefix" do
      content = "app.use('/static', express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)

      paths.size.should eq(1)
      paths[0]["static_path"].should eq("/static")
      paths[0]["file_path"].should eq("public")
    end

    it "extracts Express static paths without prefix" do
      content = "app.use(express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)

      paths.size.should eq(1)
      paths[0]["static_path"].should eq("/")
      paths[0]["file_path"].should eq("public")
    end

    it "extracts Koa serve paths" do
      content = "app.use(serve('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)

      paths.size.should eq(1)
      paths[0]["static_path"].should eq("/")
      paths[0]["file_path"].should eq("public")
    end

    it "extracts Koa mount + serve paths" do
      content = "app.use(mount('/static', serve('public')))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)

      paths.size.should eq(1)
      paths[0]["static_path"].should eq("/static")
      paths[0]["file_path"].should eq("public")
    end

    it "returns empty for content with no static paths" do
      content = "app.get('/users', handler);"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)

      paths.should be_empty
    end
  end

  describe ".extract_body_params" do
    it "extracts destructured body params" do
      handler = "{ const { name, email } = req.body; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)

      param_names = endpoint.params.map(&.name)
      param_names.should contain("name")
      param_names.should contain("email")
    end

    it "extracts direct body property access" do
      handler = "{ const name = req.body.name; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
    end

    it "extracts bracket notation body access" do
      handler = "{ const val = req.body['field']; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "field" && p.param_type == "json" }.should be_true
    end
  end

  describe ".extract_query_params" do
    it "extracts destructured query params" do
      handler = "{ const { page, limit } = req.query; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)

      param_names = endpoint.params.map(&.name)
      param_names.should contain("page")
      param_names.should contain("limit")
    end

    it "extracts direct query property access" do
      handler = "{ const search = req.query.search; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
    end
  end

  describe ".extract_header_params" do
    it "extracts bracket notation header access" do
      handler = "{ const token = req.headers['authorization']; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "authorization" && p.param_type == "header" }.should be_true
    end

    it "extracts Express req.header() call" do
      handler = "{ const ct = req.header('content-type'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "content-type" && p.param_type == "header" }.should be_true
    end
  end

  describe ".extract_cookie_params" do
    it "extracts Express cookie access" do
      handler = "{ const session = req.cookies.session_id; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)

      endpoint.params.any? { |p| p.name == "session_id" && p.param_type == "cookie" }.should be_true
    end
  end
end
