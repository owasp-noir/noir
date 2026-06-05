require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_route_extractor"

describe Noir::JSRouteExtractor do
  describe "normalize_http_method" do
    it "normalizes DEL to DELETE" do
      Noir::JSRouteExtractor.normalize_http_method("DEL").should eq("DELETE")
      Noir::JSRouteExtractor.normalize_http_method("del").should eq("DELETE")
    end

    it "keeps standard methods unchanged" do
      Noir::JSRouteExtractor.normalize_http_method("GET").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("POST").should eq("POST")
      Noir::JSRouteExtractor.normalize_http_method("PUT").should eq("PUT")
      Noir::JSRouteExtractor.normalize_http_method("DELETE").should eq("DELETE")
      Noir::JSRouteExtractor.normalize_http_method("PATCH").should eq("PATCH")
      Noir::JSRouteExtractor.normalize_http_method("HEAD").should eq("HEAD")
    end

    it "uppercases methods" do
      Noir::JSRouteExtractor.normalize_http_method("get").should eq("GET")
      Noir::JSRouteExtractor.normalize_http_method("post").should eq("POST")
    end

    it "keeps ALL as ALL" do
      Noir::JSRouteExtractor.normalize_http_method("ALL").should eq("ALL")
      Noir::JSRouteExtractor.normalize_http_method("all").should eq("ALL")
    end

    it "keeps OPTIONS" do
      Noir::JSRouteExtractor.normalize_http_method("OPTIONS").should eq("OPTIONS")
    end

    it "returns uppercased unknown methods" do
      Noir::JSRouteExtractor.normalize_http_method("custom").should eq("CUSTOM")
    end
  end

  describe "extract_body_params" do
    it "extracts destructured body params" do
      handler = "{ const { name, email } = req.body; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
      endpoint.params.any? { |p| p.name == "email" && p.param_type == "json" }.should be_true
    end

    it "extracts direct property access body params" do
      handler = "{ const name = req.body.username; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "username" && p.param_type == "json" }.should be_true
    end

    it "extracts bracket notation body params" do
      handler = "{ const val = req.body['token']; }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "token" && p.param_type == "json" }.should be_true
    end

    it "extracts Hono-style json body params" do
      handler = "{ const { name, age } = await c.req.json(); }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "name" && p.param_type == "json" }.should be_true
      endpoint.params.any? { |p| p.name == "age" && p.param_type == "json" }.should be_true
    end

    it "extracts Hono-style parseBody form params" do
      handler = "{ const { file, description } = await c.req.parseBody(); }"
      endpoint = Endpoint.new("/test", "POST")
      Noir::JSRouteExtractor.extract_body_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "file" && p.param_type == "form" }.should be_true
      endpoint.params.any? { |p| p.name == "description" && p.param_type == "form" }.should be_true
    end
  end

  describe "extract_query_params" do
    it "extracts destructured query params" do
      handler = "{ const { page, limit } = req.query; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "page" && p.param_type == "query" }.should be_true
      endpoint.params.any? { |p| p.name == "limit" && p.param_type == "query" }.should be_true
    end

    it "extracts direct query property access" do
      handler = "{ const p = req.query.search; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
    end

    it "extracts Hono-style query params" do
      handler = "{ const q = c.req.query('search'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "search" && p.param_type == "query" }.should be_true
    end

    it "extracts Hono-style queries params" do
      handler = "{ const tags = c.req.queries('tag'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_query_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "tag" && p.param_type == "query" }.should be_true
    end
  end

  describe "extract_header_params" do
    it "extracts bracket notation header params" do
      handler = "{ const auth = req.headers['authorization']; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "authorization" && p.param_type == "header" }.should be_true
    end

    it "extracts dot notation header params" do
      handler = "{ const ct = req.headers.host; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "host" && p.param_type == "header" }.should be_true
    end

    it "extracts Express-style req.header() params" do
      handler = "{ const ct = req.header('Content-Type'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "Content-Type" && p.param_type == "header" }.should be_true
    end

    it "extracts Koa-style ctx.get() header params" do
      handler = "{ const auth = ctx.get('Authorization'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "Authorization" && p.param_type == "header" }.should be_true
    end

    it "extracts Hono-style header params" do
      handler = "{ const token = c.req.header('X-API-Key'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_header_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "X-API-Key" && p.param_type == "header" }.should be_true
    end
  end

  describe "extract_cookie_params" do
    it "extracts Express-style cookie params" do
      handler = "{ const sid = req.cookies.session_id; }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "session_id" && p.param_type == "cookie" }.should be_true
    end

    it "extracts Koa-style cookie params" do
      handler = "{ const token = ctx.cookies.get('session'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "session" && p.param_type == "cookie" }.should be_true
    end

    it "extracts Hono-style getCookie params" do
      handler = "{ const val = getCookie(c, 'auth_token'); }"
      endpoint = Endpoint.new("/test", "GET")
      Noir::JSRouteExtractor.extract_cookie_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "auth_token" && p.param_type == "cookie" }.should be_true
    end
  end

  describe "extract_path_params" do
    it "extracts Express-style path params with dot notation" do
      handler = "{ const id = req.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "extracts bracket notation path params" do
      handler = "{ const id = req.params['userId']; }"
      endpoint = Endpoint.new("/test/:userId", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "userId" && p.param_type == "path" }.should be_true
    end

    it "extracts Hono-style path params" do
      handler = "{ const id = c.req.param('id'); }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "extracts Koa-style path params" do
      handler = "{ const id = ctx.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      endpoint.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    end

    it "does not duplicate existing path params" do
      handler = "{ const id = req.params.id; }"
      endpoint = Endpoint.new("/test/:id", "GET")
      endpoint.push_param(Param.new("id", "", "path"))
      Noir::JSRouteExtractor.extract_path_params(handler, endpoint)
      path_params = endpoint.params.select { |p| p.name == "id" && p.param_type == "path" }
      path_params.size.should eq(1)
    end
  end

  describe "extract_static_paths" do
    it "extracts Express static with prefix" do
      content = "app.use('/static', express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/static" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Express static without prefix" do
      content = "app.use(express.static('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Koa-style serve" do
      content = "app.use(serve('public'))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/" && p["file_path"] == "public" }.should be_true
    end

    it "extracts Koa mount + serve" do
      content = "app.use(mount('/assets', serve('static')))"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.any? { |p| p["static_path"] == "/assets" && p["file_path"] == "static" }.should be_true
    end

    it "returns empty for no static paths" do
      content = "app.get('/users', handler);"
      paths = Noir::JSRouteExtractor.extract_static_paths(content)
      paths.size.should eq(0)
    end

    it "skips a minified single line carrying a static-mount substring" do
      # The `.use(express.static(...))` substring passes the cheap
      # prefilter, but the minified guard must short-circuit before the
      # static-mount regexes run across a multi-KB single line (#1903).
      content = "app.use(express.static('public'));" + ("var _p=function(){return 0};" * 300)
      Noir::JSRouteExtractor.minified_content?(content).should be_true # sanity: it is minified
      Noir::JSRouteExtractor.extract_static_paths(content).size.should eq(0)
    end
  end

  describe "minified_content?" do
    it "is false for ordinary multi-line source" do
      content = <<-JS
        const express = require("express");
        const app = express();
        app.get("/users", (req, res) => res.json([]));
        JS
      Noir::JSRouteExtractor.minified_content?(content).should be_false
    end

    it "is true for a single line past the threshold (bundle signature)" do
      # One ~6 KB line, no newlines — the webpack/rollup bundle shape.
      content = "var app=e();" + ("var _pad=function(a,b){return a+b};" * 200) +
                "app.get('/x',h);"
      Noir::JSRouteExtractor.minified_content?(content).should be_true
    end

    it "is true for a multi-line bundle dominated by long lines" do
      # A few enormous lines — high average line length.
      chunk = "a" * 6000
      content = "#{chunk}\n#{chunk}\n#{chunk}\n"
      Noir::JSRouteExtractor.minified_content?(content).should be_true
    end

    it "does NOT classify a route file that merely carries one fat line" do
      # Finding #1 regression guard: a real module with many short route
      # lines plus one >5000-byte inline-JSON line must NOT be skipped —
      # its endpoints have to survive. The long line trips condition (1)
      # but the low average line length fails condition (2).
      fat = "app.post('/data', (req, res) => res.json(" + ("{\"k\":\"v\"}," * 700) + "));"
      routes = Array.new(40) { |i| "app.get('/r#{i}', (req, res) => res.send('#{i}'));" }.join("\n")
      content = "#{routes}\n#{fat}\n#{routes}\n"
      Noir::JSRouteExtractor.minified_content?(content).should be_false
    end

    it "pins the default 5000-byte line boundary" do
      Noir::JSRouteExtractor.minified_content?("a" * 4999).should be_false
      Noir::JSRouteExtractor.minified_content?("a" * 5000).should be_true
    end

    it "resets the line length on each newline" do
      # Two 4999-byte lines: neither reaches the per-line threshold.
      content = ("a" * 4999) + "\n" + ("a" * 4999)
      Noir::JSRouteExtractor.minified_content?(content).should be_false
    end

    it "measures bytes, not characters (multi-byte aware)" do
      # 1667 * 3-byte '€' = 5001 bytes on one line.
      Noir::JSRouteExtractor.minified_content?("€" * 1667).should be_true
    end

    it "respects custom line and average thresholds" do
      content = "x" * 100                                                         # single 100-byte line
      Noir::JSRouteExtractor.minified_content?(content, 200).should be_false      # line threshold not met
      Noir::JSRouteExtractor.minified_content?(content, 50, 50).should be_true    # both met
      Noir::JSRouteExtractor.minified_content?(content, 50, 1000).should be_false # avg threshold not met
    end
  end

  describe "extract_routes" do
    it "returns empty for non-existent file" do
      routes = Noir::JSRouteExtractor.extract_routes("/nonexistent/file.js")
      routes.size.should eq(0)
    end

    it "skips minified bundles even when they contain route shapes" do
      # The packed `app.get('/leak', ...)` on one long line must not be
      # tokenized or extracted (issue #1903). extract_routes guards on
      # File.exists?, so write a real temp file to exercise the path.
      content = "!function(e){var app=e();" +
                ("var _0x=function(a,b){return a.concat(b)};" * 200) +
                "app.get('/leak',function(q,r){r.send('x')});}(window);"
      file = File.tempfile("bundle", ".js", &.print(content))
      begin
        routes = Noir::JSRouteExtractor.extract_routes(file.path, content)
        routes.size.should eq(0)
      ensure
        file.delete
      end
    end

    it "still extracts routes from ordinary express source" do
      content = <<-JS
        const express = require("express");
        const app = express();
        app.get("/users", (req, res) => res.json([]));
        JS
      file = File.tempfile("app", ".js", &.print(content))
      begin
        routes = Noir::JSRouteExtractor.extract_routes(file.path, content)
        routes.any? { |r| r.url == "/users" && r.method == "GET" }.should be_true
      ensure
        file.delete
      end
    end
  end

  describe "test_stub_only?" do
    it "skips files importing pretender without an HTTP server lib" do
      content = <<-JS
        import Pretender from "pretender";
        const server = new Pretender();
        server.get("/api/users", () => [200, {}, "[]"]);
        JS
      Noir::JSRouteExtractor.test_stub_only?("/app/tests/user-test.js", content).should be_true
    end

    it "keeps the file when express is also imported (lenient path-marker route)" do
      # Library + the lenient TEST_STUB_PATH_MARKERS honor an
      # HTTP-server-import exemption so legit test-server harnesses
      # keep their routes. `/dist/` is part of the lenient set
      # (bundled output paths) — it triggers the path-marker code
      # path but the exemption keeps it scanned when an HTTP server
      # lib is imported. Strict markers like `/cypress/` and `/e2e/`
      # skip unconditionally and are covered by separate specs.
      content = <<-JS
        import express from "express";
        import Pretender from "pretender";
        const app = express();
        app.get("/api/users", (req, res) => res.json([]));
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/dist/server-bundle.js",
        content
      ).should be_false
    end

    it "skips strict-filename test markers unconditionally" do
      # Filenames like `foo.test.ts` / `bar.e2e-spec.ts` never
      # define real routes — even when the file imports an HTTP
      # server lib for type-only references (NestJS e2e style).
      content = <<-JS
        import { NestExpressApplication } from "@nestjs/platform-express";
        import request from "supertest";
        await request(app).get("/api/users");
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/users/users.controller.e2e-spec.ts",
        content
      ).should be_true
    end

    it "skips pretender helpers by path even without import markers" do
      content = <<-JS
        export default function (helper) {
          this.post("/presence/update", () => helper.response(200, {}));
        }
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/frontend/tests/helpers/presence-pretender.js",
        content
      ).should be_true
    end

    it "leaves non-test files untouched" do
      content = <<-JS
        const express = require("express");
        const app = express();
        app.get("/api/users", (req, res) => res.json([]));
        JS
      Noir::JSRouteExtractor.test_stub_only?("/app/src/server.js", content).should be_false
    end

    it "skips Jest-style test files by name" do
      content = <<-JS
        import request from "supertest";
        describe("users", () => {
          it("works", async () => {
            await request(app).get("/api/users").expect(200);
          });
        });
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/packages/cli/test/integration/users.controller.test.ts",
        content
      ).should be_true
    end

    it "skips files under /__tests__/ directories" do
      content = <<-JS
        await client.get("/foo");
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/modules/data-table/__tests__/data-table.controller.test.ts",
        content
      ).should be_true
    end

    it "skips Cypress e2e specs" do
      content = <<-JS
        /// <reference types="cypress" />
        describe("login", () => {
          cy.request("POST", "/api/login");
        });
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/e2e-tests/cypress/tests/login_spec.ts",
        content
      ).should be_true
    end

    it "skips Playwright e2e specs" do
      content = <<-JS
        import { test, expect } from "@playwright/test";
        test("ping", async ({ request }) => {
          await request.get("/api/health");
        });
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/tests/e2e/health.spec.ts",
        content
      ).should be_true
    end

    it "skips supertest harnesses that don't otherwise look like tests" do
      # Regression: expressjs/express keeps its supertest suites under
      # `test/`/`test/acceptance/` with plain `*.js` filenames (e.g.
      # `app.router.js`, `acceptance/web-service.js`). None match the
      # `.test.`/`.spec.` filename convention or a TEST_STUB_PATH_MARKER,
      # and they `require('../')` instead of literal `'express'`, so
      # without a supertest marker the test client's
      # `request(app).get('/api/users?api-key=foo')` chain leaks through
      # as a route.
      content = <<-JS
        var request = require('supertest')
          , app = require('../../examples/web-service');

        describe('web-service', function(){
          it('responds', function(done){
            request(app).get('/api/users?api-key=foo').expect(200, done);
          })
        })
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/test/acceptance/web-service.js",
        content
      ).should be_true
    end

    it "keeps supertest-using files that also import the real server lib" do
      # Exemption guard: a regular project file that imports both
      # supertest and express should still scan — the `app.get(...)`
      # registrations are real, and the supertest call sits next to
      # them only because the file boots its own test harness.
      content = <<-JS
        import express from "express";
        import request from "supertest";
        const app = express();
        app.get("/api/users", (req, res) => res.json([]));
        request(app).get("/api/users").expect(200);
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/server.js",
        content
      ).should be_false
    end

    it "skips Ember mirage stub-server configs by /mirage/ path" do
      # Regression: TryGhost/Ghost's `ghost/admin/mirage/config/*.js`
      # files configure an Ember mirage stub server. `server.get(...)`
      # / `server.post(...)` are mock-server handlers, not real
      # Express routes — Ghost alone parks ~53 phantom endpoints
      # here.
      content = <<-JS
        import {paginatedResponse} from '../utils';
        export default function mockOffers(server) {
          server.post('/offers/');
          server.get('/offers/', paginatedResponse('offers'));
        }
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/ghost/admin/mirage/config/offers.js",
        content
      ).should be_true
    end

    it "skips e2e helper mock servers by /e2e/ path" do
      content = <<-TS
        import express from "express";
        const app = express();
        app.get("/v1/products/:id", (req, res) => res.json({}));
        TS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/e2e/helpers/services/stripe/fake-stripe-server.ts",
        content
      ).should be_true
    end

    it "skips files using other HTTP-client libs (got, purest, ky, ...)" do
      # Regression: Strapi's `providers-registry.js` uses `purest`
      # for OAuth provider calls — `discord.get('users/@me')` is an
      # outbound API call, not a Koa route. The same pattern shows
      # up across the Node ecosystem with got, ky, superagent,
      # node-fetch, ofetch, undici, request — none of these libs
      # are ever used to register routes.
      content = <<-JS
        const purest = require('purest');
        const discord = purest({ provider: 'discord' });
        discord.get('users/@me');
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/providers.js",
        content
      ).should be_true
    end

    it "skips axios-only HTTP-client files" do
      # Regression: mastodon `app/javascript/entrypoints/public.tsx`
      # chains `axios.get('/api/v1/accounts/lookup', { params: ... })`
      # — a browser-side AJAX call, not an Express route. axios is
      # almost exclusively used to make outbound HTTP calls, so its
      # presence alongside `.get(`/`.post(` shapes is a strong signal
      # the file isn't a server.
      content = <<-TS
        import axios from "axios";
        axios.get("/api/v1/foo", { params: { x: 1 } });
        TS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/api/client.ts",
        content
      ).should be_true
    end

    it "keeps axios files that also import a real HTTP server lib" do
      # Exemption guard: a real backend that uses axios internally for
      # outbound calls should still scan when it also imports
      # express/fastify/...
      content = <<-JS
        import express from "express";
        import axios from "axios";
        const app = express();
        app.get("/proxy", async (req, res) => {
          const data = await axios.get("https://upstream");
          res.json(data.data);
        });
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/src/server.js",
        content
      ).should be_false
    end

    it "skips files under Rails Webpacker app/javascript/" do
      # Regression: Mastodon's redux action modules under
      # `app/javascript/mastodon/actions/*.js` use `api().get('/url')`
      # via a local axios wrapper. The `axios` filename hint doesn't
      # fire because the wrapper hides the import, but the
      # `app/javascript/` path marker is unambiguous on Rails-with-
      # Webpacker layouts.
      content = <<-JS
        import api from "../api";
        api().get("/api/v1/accounts/lookup");
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/javascript/mastodon/actions/accounts.js",
        content
      ).should be_true
    end

    it "skips .test-d.ts type-only test files" do
      # Regression: fastify/fastify's `test/types/*.test-d.ts` files
      # register sample routes purely to assert their inferred typings.
      # The `.test.`/`.spec.`/`-test.`/`-spec.` markers don't catch the
      # `.test-d.` suffix that tsd / expect-type use for type-test
      # files, so the JSParser was happy to emit every shape as a
      # route.
      content = <<-TS
        import fastify from "fastify";
        const app = fastify();
        app.get("/typed", { schema: {} }, (req, reply) => reply.send({}));
        app.post("/typed", (req, reply) => reply.send({}));
        TS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/test/types/schema.test-d.ts",
        content
      ).should be_true
    end

    it "skips bundled dist/ output files" do
      content = <<-JS
        // webpack bundle output with thousands of .get( / .post( noise
        app.get("/x");
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/app/.github/actions/check-results/dist/index.js",
        content
      ).should be_true
    end

    it "skips browser scripts under public/ without a server import" do
      # Regression #1903: `apps/*/public/lib/*.js` browser bundles
      # carry `app.get(...)`-shaped calls but are static output, never
      # route registrations. No express import → no exemption.
      content = <<-JS
        const app = window.__bus;
        app.get("/public-leak", (q, r) => r.render());
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/repo/apps/web/public/lib/widget.js",
        content
      ).should be_true
    end

    it "keeps public/ files that genuinely import a server lib" do
      # Exemption guard: the rare hand-written SSR entrypoint that lives
      # under public/ and actually runs express should still scan.
      content = <<-JS
        import express from "express";
        const app = express();
        app.get("/real", (req, res) => res.json([]));
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/repo/apps/web/public/server.js",
        content
      ).should be_false
    end

    it "skips Apollo RESTDataSource outbound clients" do
      # Regression #1903: generated BFF data sources extend
      # RESTDataSource and call `this.get('/x')` / `this.post('/y')` as
      # OUTBOUND requests. The `@apollo/datasource-rest` import marks
      # them as clients, not servers.
      content = <<-TS
        import { RESTDataSource } from "@apollo/datasource-rest";
        export class UsersAPI extends RESTDataSource {
          getUser(id: string) { return this.get(`/users/${id}`); }
          createUser(b: object) { return this.post("/users", { body: b }); }
        }
        TS
      Noir::JSRouteExtractor.test_stub_only?(
        "/repo/packages/bff/src/UsersDataSource.ts",
        content
      ).should be_true
    end

    it "also recognizes the legacy apollo-datasource-rest package name" do
      content = <<-JS
        const { RESTDataSource } = require("apollo-datasource-rest");
        class API extends RESTDataSource {
          getThing() { return this.get("/thing"); }
        }
        JS
      Noir::JSRouteExtractor.test_stub_only?(
        "/repo/src/datasources/thing.js",
        content
      ).should be_true
    end

    it "keeps a file importing both a data source lib and a real server lib" do
      # Precedence guard: the HTTP-server-import exemption wins, so a
      # file that imports @apollo/datasource-rest AND express is still
      # scanned (its app.get(...) registrations are real).
      content = <<-TS
        import express from "express";
        import { RESTDataSource } from "@apollo/datasource-rest";
        const app = express();
        app.get("/real", (req, res) => res.json([]));
        TS
      Noir::JSRouteExtractor.test_stub_only?(
        "/repo/src/server.ts",
        content
      ).should be_false
    end
  end
end
