require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_route_extractor"

describe Noir::JSRouteExtractor do
  express_router = <<-JS
    const express = require('express');
    const router = express.Router();
    router.post('/assign', (req, res) => res.json({}));
    module.exports = router;
    JS

  mocha_suite = <<-JS
    const express = require('express');
    describe('Router', function () {
      var router = express.Router();
      router.get('/foo', function (req, res) { res.end(); });
    });
    JS

  describe "test_stub_only? underscore and .tst. names" do
    it "skips an underscore-named mocha suite that imports express" do
      content = <<-JS
        const express = require('express');
        const request = require('supertest');
        describe('context', () => {
          const app = express();
          app.get('/context/:scope', (req, res) => res.json({}));
        });
        JS
      Noir::JSRouteExtractor.test_stub_only?("/app/test/unit/admin/context_spec.js", content).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/test/unit/admin/context_test.js", content).should be_true
    end

    it "keeps underscore-named production routers that import an HTTP server" do
      Noir::JSRouteExtractor.test_stub_only?("/app/routes/ab_test.js", express_router).should be_false
      Noir::JSRouteExtractor.test_stub_only?("/app/routes/api_spec.js", express_router).should be_false
    end

    it "skips an underscore-named Deno test with no server import" do
      content = <<-TS
        import { App } from "fresh";
        Deno.test("redirect", () => {
          new App().get("/old", (ctx) => ctx.redirect("/new"));
        });
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/src/context_test.tsx", content).should be_true
    end

    it "skips an underscore-named Deno test that imports a server library" do
      content = <<-TS
        import { Hono } from "hono";
        Deno.test("hono", () => {
          new Hono().get("/x", (c) => c.text("x"));
        });
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/src/app_test.ts", content).should be_true
    end

    it "skips fastify .tst. type tests unconditionally" do
      content = <<-TS
        import fastify from 'fastify'
        const server = fastify()
        server.get('/get', getHandler)
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/test/types/reply.tst.ts", content).should be_true
    end
  end

  describe "test_stub_only? fixture trees and test servers" do
    it "skips a fixture app under test/fixtures/ that imports no server" do
      content = "module.exports = app => { app.get('/pathFor', function () {}); };"
      Noir::JSRouteExtractor.test_stub_only?("/app/packages/egg/test/fixtures/apps/helper/app/router.js", content).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/tests/fixtures/app/router.js", content).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/src/__fixtures__/router.js", content).should be_true
    end

    it "keeps a fixture server that really imports express" do
      Noir::JSRouteExtractor.test_stub_only?("/app/test/fixtures/server.js", express_router).should be_false
    end

    it "does not treat a bare fixtures/ directory as a test tree" do
      content = "module.exports = app => { app.get('/fixtures/today', function () {}); };"
      Noir::JSRouteExtractor.test_stub_only?("/app/src/api/fixtures/routes.js", content).should be_false
    end

    it "skips throwaway @epic-web/test-server routes" do
      content = <<-TS
        import { createTestHttpServer } from '@epic-web/test-server/http'
        export default () => createTestHttpServer({
          defineRoutes(router) {
            router.post('/analytics-bypass', () => new Response(null))
          },
        })
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/vitest.setup.ts", content).should be_true
    end

    it "keeps a test-server file that also imports a real server library" do
      content = <<-TS
        import express from 'express'
        import { createTestHttpServer } from '@epic-web/test-server/http'
        const app = express()
        app.get('/x', (req, res) => res.end())
        TS
      Noir::JSRouteExtractor.test_stub_only?("/app/src/server.ts", content).should be_false
    end
  end

  describe "test_file?" do
    it "treats a describe suite under test/ as a test even when it imports express" do
      Noir::JSRouteExtractor.test_file?("/app/test/Router.js", mocha_suite).should be_true
      Noir::JSRouteExtractor.test_file?("/app/tests/Router.js", mocha_suite).should be_true
      Noir::JSRouteExtractor.test_stub_only?("/app/test/Router.js", mocha_suite).should be_true
    end

    it "recognises Lab.script and describe.only suites" do
      lab = "const lab = exports.lab = Lab.script();\nlab.test('x', () => { server.route({ method: 'GET', path: '/x' }); });"
      Noir::JSRouteExtractor.test_file?("/app/test/server.js", lab).should be_true
      only = "describe.only('x', () => {\n});"
      Noir::JSRouteExtractor.test_file?("/app/test/server.js", only).should be_true
    end

    it "needs a test name or tree when the suite call is outside test directories" do
      Noir::JSRouteExtractor.test_file?("/app/src/server.js", mocha_suite).should be_false
      Noir::JSRouteExtractor.test_file?("/app/src/routes.test.js", express_router).should be_true
      Noir::JSRouteExtractor.test_file?("/app/e2e/helpers/server.js", express_router).should be_true
    end

    it "keeps a route file under test/ when it has no suite" do
      Noir::JSRouteExtractor.test_file?("/app/test/helpers_server.js", express_router).should be_false
    end

    it "ignores the zod/Joi .describe( annotation" do
      content = <<-TS
        const schema = z.object({ id: z.string().describe('the id') });
        router.post('/items', handler);
        TS
      Noir::JSRouteExtractor.test_file?("/app/test/routes.ts", content).should be_false
    end

    it "does not judge the directories above the scan base" do
      locator = CodeLocator.instance
      previous_bases = locator.scan_base_paths
      begin
        locator.scan_base_paths = ["/home/test/app"]
        Noir::JSRouteExtractor.test_file?("/home/test/app/src/server.js", mocha_suite).should be_false
        Noir::JSRouteExtractor.test_file?("/home/test/app/test/Router.js", mocha_suite).should be_true
      ensure
        locator.scan_base_paths = previous_bases
      end
    end
  end
end
