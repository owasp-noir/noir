require "../../spec_helper"
require "../../../src/miniparsers/js_parser"

describe Noir::JSParser do
  describe "detect_framework" do
    it "detects express framework" do
      parser = Noir::JSParser.new("const express = require('express');")
      parser.detect_framework.should eq(:express)
    end

    it "detects fastify framework" do
      parser = Noir::JSParser.new("const fastify = require('fastify')();")
      parser.detect_framework.should eq(:fastify)
    end

    it "detects restify framework" do
      parser = Noir::JSParser.new("const restify = require('restify');")
      parser.detect_framework.should eq(:restify)
    end

    it "returns unknown for unrecognized frameworks" do
      parser = Noir::JSParser.new("const app = {};")
      parser.detect_framework.should eq(:unknown)
    end
  end

  describe "parse_routes" do
    it "parses basic Express GET route" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/users', (req, res) => {});
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/users" }.should be_true
    end

    it "parses basic Express POST route" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.post('/users', (req, res) => {});
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "POST" && r.path == "/users" }.should be_true
    end

    it "parses multiple HTTP methods" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/items', handler);
      app.post('/items', handler);
      app.put('/items/:id', handler);
      app.delete('/items/:id', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/items" }.should be_true
      routes.any? { |r| r.method == "POST" && r.path == "/items" }.should be_true
      routes.any? { |r| r.method == "PUT" && r.path == "/items/:id" }.should be_true
      routes.any? { |r| r.method == "DELETE" && r.path == "/items/:id" }.should be_true
    end

    it "extracts path parameters" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/users/:id/posts/:postId', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      route = routes.find { |r| r.path == "/users/:id/posts/:postId" }
      route.should_not be_nil
      if route
        param_names = route.params.map(&.name)
        param_names.should contain("id")
        param_names.should contain("postId")
      end
    end

    it "handles router with prefix mounting" do
      code = <<-JS
      const express = require('express');
      const app = express();
      const router = express.Router();
      router.get('/items', handler);
      app.use('/api', router);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/api/items" }.should be_true
    end

    it "parses route chaining with app.route()" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.route('/books')
        .get(handler)
        .post(handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/books" }.should be_true
      routes.any? { |r| r.method == "POST" && r.path == "/books" }.should be_true
    end

    it "parses Fastify routes" do
      code = <<-JS
      const fastify = require('fastify')();
      fastify.get('/health', async (req, reply) => {});
      fastify.post('/data', async (req, reply) => {});
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/health" }.should be_true
      routes.any? { |r| r.method == "POST" && r.path == "/data" }.should be_true
    end

    it "parses Restify routes" do
      code = <<-JS
      const restify = require('restify');
      const server = restify.createServer();
      server.get('/items', handler);
      server.post('/items', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/items" }.should be_true
      routes.any? { |r| r.method == "POST" && r.path == "/items" }.should be_true
    end

    it "resolves constants in route paths" do
      code = <<-JS
      const express = require('express');
      const app = express();
      const API_PREFIX = '/api/v1';
      app.get(API_PREFIX + '/users', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/api/v1/users" }.should be_true
    end

    it "handles template literal paths" do
      code = <<-JS
      const express = require('express');
      const app = express();
      const version = 'v2';
      app.get(`/api/${version}/items`, handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/api/v2/items" }.should be_true
    end

    it "deduplicates routes" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/users', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      get_user_routes = routes.select { |r| r.method == "GET" && r.path == "/users" }
      get_user_routes.size.should eq(1)
    end

    it "filters invalid paths" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/valid/path', handler);
      JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.each do |route|
        route.path.includes?("://").should be_false
      end
    end

    it "does not exceed max iterations" do
      code = <<-JS
      const express = require('express');
      const app = express();
      app.get('/test', handler);
      JS
      parser = Noir::JSParser.new(code)
      parser.parse_routes

      parser.hit_max_iterations?.should be_false
    end
  end

  describe "JSRoutePattern" do
    it "stores method and path" do
      pattern = Noir::JSRoutePattern.new("GET", "/users")
      pattern.method.should eq("GET")
      pattern.path.should eq("/users")
    end

    it "stores raw_path" do
      pattern = Noir::JSRoutePattern.new("GET", "/api/users", "/users")
      pattern.raw_path.should eq("/users")
    end

    it "stores params" do
      pattern = Noir::JSRoutePattern.new("GET", "/users/:id")
      pattern.push_param(Param.new("id", "", "path"))
      pattern.params.size.should eq(1)
      pattern.params[0].name.should eq("id")
    end
  end
end
