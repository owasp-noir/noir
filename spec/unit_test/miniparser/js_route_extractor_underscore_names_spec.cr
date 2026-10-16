require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/logger"
require "../../../src/models/endpoint"
require "../../../src/miniparsers/js_route_extractor"

describe Noir::JSRouteExtractor do
  # No server import at all: the router is handed in by the app.
  router_module = "module.exports = function register(app) { app.get('/speed', (req, res) => res.end()); };"
  fastify_plugin = <<-JS
    const fp = require('fastify-plugin');
    module.exports = fp(async function abTest(fastify) {
      fastify.get('/ab', async () => ({ variant: 'a' }));
    });
    JS

  describe "underscore-named files" do
    it "keeps snake_case production names that hold no suite" do
      {"/app/routes/speed_test.js", "/app/routes/user_spec.js", "/app/convex/load_test.ts"}.each do |path|
        Noir::JSRouteExtractor.test_file?(path, router_module).should be_false
        Noir::JSRouteExtractor.test_stub_only?(path, router_module).should be_false
      end
      Noir::JSRouteExtractor.test_stub_only?("/app/routes/ab_test.js", fastify_plugin).should be_false
    end

    it "skips an underscore-named file that holds a describe or Deno.test suite" do
      mocha = "const express = require('express');\ndescribe('x', () => {\n  express().get('/p', () => {});\n});"
      deno = "import { Hono } from 'hono';\nDeno.test('x', () => { new Hono().get('/p', (c) => c.text('p')); });"
      Noir::JSRouteExtractor.test_file?("/app/src/ab_spec.js", mocha).should be_true
      Noir::JSRouteExtractor.test_file?("/app/src/ab_test.ts", deno).should be_true
    end

    it "ignores a zod .describe( annotation in a production snake_case file" do
      content = "const s = z.object({ id: z.string().describe('the id') });\nrouter.post('/items', handler);"
      Noir::JSRouteExtractor.test_file?("/app/routes/ab_test.ts", content).should be_false
    end
  end

  describe "hyphen-named files" do
    it "stay conditional on a server import" do
      express_router = "const express = require('express');\nconst router = express.Router();\nrouter.get('/x', h);"
      Noir::JSRouteExtractor.test_stub_only?("/app/routes/ab-test.js", express_router).should be_false
      Noir::JSRouteExtractor.test_stub_only?("/app/routes/ab-test.js", router_module).should be_true
    end
  end

  describe "test_named_or_in_test_tree?" do
    it "judges names and test trees, never the underscore forms" do
      Noir::JSRouteExtractor.test_named_or_in_test_tree?("a.test.ts", "/src/a.test.ts").should be_true
      Noir::JSRouteExtractor.test_named_or_in_test_tree?("a.js", "/e2e/a.js").should be_true
      Noir::JSRouteExtractor.test_named_or_in_test_tree?("ab_test.ts", "/src/ab_test.ts").should be_false
      Noir::JSRouteExtractor.test_named_or_in_test_tree?("ab-test.ts", "/src/ab-test.ts").should be_false
    end
  end
end
