require "../../spec_helper"
require "../../../src/miniparsers/js_parser"

describe Noir::JSParser do
  describe "empty route paths" do
    it "keeps '' on app/router receivers, including an inline Fastify plugin's instance" do
      code = <<-JS
        const fastify = require('fastify')();
        fastify.register(async function (f) {
          f.get('', async () => 'x');
        }, { prefix: '/items' });
        const r = express.Router();
        r.get('', (req, res) => {});
        app.get('', (req, res) => {});
        JS
      routes = Noir::JSParser.new(code).parse_routes
      routes.count { |route| route.raw_path.empty? && route.method == "GET" }.should eq(3)
    end

    it "drops '' on cache and HTTP-client receivers" do
      code = <<-JS
        const express = require('express');
        cache.get('', (err, v) => {});
        client.post('', body);
        api.post('', payload);
        JS
      Noir::JSParser.new(code).parse_routes.should be_empty
    end
  end

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
        app.query('/items/search', handler);
        JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      routes.any? { |r| r.method == "GET" && r.path == "/items" }.should be_true
      routes.any? { |r| r.method == "POST" && r.path == "/items" }.should be_true
      routes.any? { |r| r.method == "PUT" && r.path == "/items/:id" }.should be_true
      routes.any? { |r| r.method == "DELETE" && r.path == "/items/:id" }.should be_true
      routes.any? { |r| r.method == "QUERY" && r.path == "/items/search" }.should be_true
    end

    it "extracts path parameters" do
      code = <<-JS
        const express = require('express');
        const app = express();
        app.get('/users/:id/posts/:postId', handler);
        JS
      parser = Noir::JSParser.new(code)
      routes = parser.parse_routes

      found = routes.find { |r| r.path == "/users/:id/posts/:postId" }
      found.should_not be_nil
      route = found.as(Noir::JSRoutePattern)
      param_names = route.params.map(&.name)
      param_names.should contain("id")
      param_names.should contain("postId")
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

  describe "route builder chains" do
    it "stops the .route() chain at the end of a semicolon-free statement" do
      # StandardJS / Prettier `semi: false` style. The chain walk used to
      # stop only at a `;`, so with none in the file it kept collecting
      # verbs from the following statements and hung them on /profile.
      code = <<-JS
        const express = require('express')
        const app = express()

        app.route('/profile')
          .get((req, res) => res.json({}))

        app.post('/orders', (req, res) => res.json({}))
        app.delete('/carts', (req, res) => res.json({}))
        JS
      routes = Noir::JSParser.new(code).parse_routes

      pairs = routes.map { |r| "#{r.method} #{r.path}" }.uniq!.sort!
      pairs.should eq(["DELETE /carts", "GET /profile", "POST /orders"])
    end

    it "still collects every verb of a real chain" do
      code = <<-JS
        const express = require('express');
        const app = express();
        app.route('/profile')
          .get((req, res) => res.json({}))
          .put((req, res) => res.json({}))
          .delete((req, res) => res.json({}));
        JS
      routes = Noir::JSParser.new(code).parse_routes

      methods = routes.select { |r| r.path == "/profile" }.map(&.method).uniq!.sort!
      methods.should eq(["DELETE", "GET", "PUT"])
    end
  end

  describe "handler-argument gate" do
    it "drops HTTP client calls that pass only a URL" do
      # NodeBB's test suite: `request` is an HTTP client, and the leading
      # `${nconf.get('url')}` is the server origin, not a mount prefix.
      code = <<-JS
        const nconf = require('nconf');
        const request = require('../src/request');

        describe('controllers', () => {
          it('loads config', async () => {
            const { body } = await request.get(`${nconf.get('url')}/api/config`);
            assert(body);
          });
        });
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.should be_empty
    end

    it "drops HTTP client calls whose only extra argument is an options bag" do
      code = <<-JS
        const request = require('../src/request');
        await request.del(`${nconf.get('url')}/api/user/revokeme/session`, { jar });
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.should be_empty
    end

    it "drops the Express settings getter" do
      code = <<-JS
        const express = require('express');
        const app = express();
        const engine = app.get('view engine');
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.should be_empty
    end

    it "drops Map and cache lookups that borrow the verb shape" do
      code = <<-JS
        const cardName = PUBLIC_CARD_ASSET_NAMES.get(`${type}/${file}`);
        await lock.delete(machineKey);
        await serveCache.del(`/post/${pid}`);
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.should be_empty
    end

    it "keeps a route whose path is a template literal with a mount prefix" do
      # The counterpart of the first example, from the same repository:
      # `${relativePath}` here IS a real Express mount prefix. Only the
      # handler argument tells the two apart.
      code = <<-JS
        const express = require('express');
        const app = express();
        app.get(`${relativePath}/ping`, pingController.ping);
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.map { |r| "#{r.method} #{r.path}" }.should contain("GET /${relativePath}/ping")
    end

    it "keeps a Fastify route whose handler lives in the options object" do
      code = <<-JS
        const fastify = require('fastify')();
        fastify.get('/shorthand', { schema, handler });
        fastify.post('/opts-then-handler', { schema }, async (req, reply) => {});
        JS
      routes = Noir::JSParser.new(code).parse_routes

      pairs = routes.map { |r| "#{r.method} #{r.path}" }
      pairs.should contain("GET /shorthand")
      pairs.should contain("POST /opts-then-handler")
    end

    it "keeps a Koa named route whose handler follows the path" do
      code = <<-JS
        const Router = require('@koa/router');
        const router = new Router();
        router.get('users.show', '/users/:id', ctx => { ctx.body = {}; });
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.map { |r| "#{r.method} #{r.path}" }.should contain("GET /users/:id")
    end

    it "rejects relative module specifiers as route paths" do
      # webpack Module Federation: `container.get('./index')` (Superset).
      code = <<-JS
        const factory = await container.get('./index');
        $.post('../jserror', { errorInfo });
        JS
      routes = Noir::JSParser.new(code).parse_routes

      routes.should be_empty
    end
  end

  describe "restify second-pass routes" do
    it "keeps routes after an applyRoutes() call" do
      code = <<-JS
        const restify = require('restify');
        const srv = restify.createServer();
        userRouter.get('/u', (req, res, next) => next());
        userRouter.applyRoutes(srv, '/users');
        srv.post({ path: '/after' }, (req, res, next) => next());
        srv.opts('/o', (req, res, next) => next());
        JS
      routes = Noir::JSParser.new(code).parse_routes.map { |r| "#{r.method} #{r.path}" }
      routes.should contain("POST /after")
      routes.should contain("OPTIONS /o")
    end

    it "reads { path } specs on any receiver but not Node http client options" do
      code = <<-JS
        const restify = require('restify');
        const http = require('http');
        const api = restify.createServer();
        api.get({ path: '/spec', version: '1.0.0' }, (req, res, next) => next());
        http.get({ host: 'upstream', path: '/remote' }, (res) => res.resume());
        JS
      routes = Noir::JSParser.new(code).parse_routes.map { |r| "#{r.method} #{r.path}" }.uniq!
      routes.should eq(["GET /spec"])
    end

    it "reads { path } routes past the first 10k tokens" do
      n = 2000
      code = String.build do |io|
        io << "const restify = require('restify');\nconst srv = restify.createServer();\n"
        n.times { |i| io << "srv.post({ path: '/r#{i}' }, (req, res, next) => next());\n" }
      end
      parser = Noir::JSParser.new(code)
      parser.parse_routes.map(&.path).uniq!.size.should eq(n)
      parser.hit_max_iterations?.should be_false
    end
  end

  describe "nested router prefixes" do
    it "applies each ancestor's prefix once on a three-level chain" do
      code = <<-JS
        const r0 = new Router();
        const r1 = new Router();
        const r2 = new Router();
        const r3 = new Router();
        r0.use('/a', r1.routes());
        r1.use('/b', r2.routes());
        r2.use('/c', r3.routes());
        r3.get('/leaf', (ctx) => { ctx.body = 1; });
        JS
      routes = Noir::JSParser.new(code).parse_routes
      routes.map(&.path).uniq!.should eq(["/a/b/c/leaf"])
    end

    it "does not memoize a router resolved mid-cycle with its parent cut" do
      code = <<-JS
        const p = express.Router();
        const q = express.Router();
        app.use("/root", q);
        p.use('/p', q);
        q.use('/q', p);
        p.get('/pp', (req, res) => res.end());
        JS
      Noir::JSParser.new(code).parse_routes.map(&.path).should contain("/root/q/pp")
    end

    it "stays bounded on a densely cyclic mount graph" do
      names = (0...14).map { |i| "r#{i}" }
      lines = names.map { |n| "const #{n} = express.Router();" }
      lines << "app.use('/root', r0);"
      names.each { |a| names.each { |b| lines << "#{a}.use('/#{b}', #{b});" unless a == b } }
      lines << "r13.get('/leaf', (req, res) => res.end());"
      routes = [] of Noir::JSRoutePattern
      elapsed = Time.measure { routes = Noir::JSParser.new(lines.join("\n")).parse_routes }
      elapsed.should be < 5.seconds
      routes.should_not be_empty
    end

    it "resolves a deep diamond lattice in bounded time and caps the prefixes" do
      depth = 16
      lines = [] of String
      (0..depth).each { |lv| lines << "const r#{lv}a = new Router();" << "const r#{lv}b = new Router();" }
      depth.times do |lv|
        %w[a b].each do |src|
          %w[a b].each { |dst| lines << "r#{lv}#{src}.use('/l#{lv}#{dst}', r#{lv + 1}#{dst}.routes());" }
        end
      end
      lines << "r#{depth}a.get('/leaf', (ctx) => { ctx.body = 1; });"

      parser = Noir::JSParser.new(lines.join("\n"))
      routes = [] of Noir::JSRoutePattern
      elapsed = Time.measure { routes = parser.parse_routes }
      elapsed.should be < 5.seconds
      routes.map(&.path).uniq!.size.should eq(Noir::JSParser::MAX_MOUNT_PREFIXES)
      parser.mount_prefixes_capped?.should be_true
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
