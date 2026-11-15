require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/javascript/express"
require "../../../../../src/cli/inspect"
require "../../../../../src/optimizer/optimizer"

private def unread_prefix_routes : Array(Endpoint)
  root = File.expand_path("../../../../functional_test/fixtures/javascript/express_unread_prefix", __DIR__)
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob(File.join(root, "**", "*")).each do |path|
    locator.register_file(path, File.read(path)) if File.file?(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  Analyzer::Javascript::Express.new(options).analyze
ensure
  CodeLocator.instance.clear_all
end

describe "Express unread prefix" do
  it "keeps the prefix claim through merging and query rendering" do
    options = create_test_options
    optimizer = EndpointOptimizer.new(NoirLogger.new(false, false, false, false), options)
    routes = unread_prefix_routes
    marked = routes.find! { |e| e.url == "/v1/prefix-users" }
    plain = Endpoint.new(marked.url, marked.method, marked.details)
    merged = optimizer.optimize_endpoints([plain, marked])
    rows = Noir::CLI::Inspect.query(merged, Noir::CLI::Inspect::Filters.new(resolutions: ["unresolved"]), false)
    rows.size.should eq(1)
    rows.first.to_json.should contain(%("resolution":{"prefix":"unresolved"}))
    rows.first.to_text.should contain("resolution=prefix:unresolved")
    routes.reject(&.resolution).map(&.url).sort!.should eq(["/fixed/prefix-factory", "/internal/prefix-health", "/prefix-plain"])
  end
end

private def express_prefix_files(files : Hash(String, String)) : Array(Endpoint)
  dir = File.tempname("express_prefix_spec")
  locator = CodeLocator.instance
  locator.clear_all
  begin
    files.each do |name, content|
      path = File.join(dir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      locator.register_file(path, content)
    end
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    Analyzer::Javascript::Express.new(options).analyze
  ensure
    locator.clear_all
    FileUtils.rm_rf(dir)
  end
end

describe "Express unread prefix mounts" do
  leaf = "const express = require('express'); const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); module.exports = router;"

  it "carries a tail through an aggregator factory and a re-export" do
    endpoints = express_prefix_files({
      "app.js"     => "const express = require('express'); const app = express(); const routes = require('./barrel'); const router = express.Router(); app.use(config.base + '/v1', routes(router));",
      "barrel.js"  => "module.exports = require('./factory');",
      "factory.js" => "const routes = require('./routes'); module.exports = (router) => { routes(router); return router; };",
      "routes.js"  => "module.exports = (router) => { router.get('/leaf', (req, res) => res.send('ok')); };",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/v1/leaf", {"prefix" => "unresolved"}}])
  end

  it "marks named re-exports and a factory result bound before mounting" do
    endpoints = express_prefix_files({
      "app.ts"     => "import express from 'express'; import { build as make } from './barrel'; const app = express(); const child = make(); app.use(process.env.API_PREFIX, child);",
      "barrel.ts"  => "export { build } from './factory';",
      "factory.ts" => "import express from 'express'; export function build() { const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); return router; }",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/leaf", {"prefix" => "unresolved"}}])
  end

  it "composes deferred nested cross-file mounts, including entirely unread calls" do
    endpoints = express_prefix_files({
      "app.js"   => "const express = require('express'); const app = express(); const api = require('./api'); app.use(config.base + '/v1', api);",
      "api.js"   => "const express = require('express'); const router = express.Router(); const child = require('./child'); router.use(getPrefix(), child); module.exports = router;",
      "child.js" => leaf,
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/v1/leaf", {"prefix" => "unresolved"}}])
  end

  it "handles inline requires, bound factories, chain links and safe and unsafe tails" do
    {"base + '/v1'" => "/v1/leaf", "base" => "/leaf", "config.base" => "/leaf", "getPrefix()" => "/leaf",
     "base + '/v1' + suffix" => "/leaf", "'/a/' + id + '/b'" => "/leaf", "base + 'relative'" => "/leaf"}.each do |expression, expected|
      endpoints = express_prefix_files({
        "app.js"   => "const express = require('express'); const app = express(); app.use(#{expression}, require('./child'));",
        "child.js" => leaf,
      })
      endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{expected, {"prefix" => "unresolved"}}])
    end
    endpoints = express_prefix_files({
      "app.js"   => "const express = require('express'); const Router = express.Router; const app = express(); const child = require('./child'); const api = Router().use(config.base + '/v1', child); app.use('/api', api);",
      "child.js" => leaf,
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/api/v1/leaf", {"prefix" => "unresolved"}}])
  end
end

describe "Express pathless middleware mounts" do
  it "does not mistake a function reference for a runtime prefix" do
    endpoints = express_prefix_files({
      "app.js"   => "const express = require('express'); const app = express(); const child = require('./child'); function auth(req, res, next) { next(); } app.use(auth, child);",
      "child.js" => "const express = require('express'); const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); module.exports = router;",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/leaf", nil}])
  end
end

describe "Express unread prefix on forwarding helpers" do
  it "marks routes a helper registers on a mounted local router" do
    endpoints = express_prefix_files({
      "app.js"     => "const express = require('express'); const app = express(); const router = express.Router(); const { register } = require('./helpers'); register(router, '/leaf', (req, res) => res.send('ok')); app.use(config.base + '/v1', router);",
      "helpers.js" => "exports.register = function (router, path, handler) { router.get(path, handler); };",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/v1/leaf", {"prefix" => "unresolved"}}])
  end
end

describe "Express imported middleware mounts" do
  it "does not mark a pathless mount behind an imported middleware or its factory" do
    ["auth", "auth()"].each do |first|
      endpoints = express_prefix_files({
        "app.js"   => "const express = require('express'); const app = express(); const auth = require('./auth'); const child = require('./child'); app.use(#{first}, child);",
        "auth.js"  => "module.exports = function auth(req, res, next) { next(); };",
        "child.js" => "const express = require('express'); const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); module.exports = router;",
      })
      endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/leaf", nil}])
    end
  end
end

describe "Express unread helper prefix composition" do
  it "joins an inherited file prefix only once with a relative local mount" do
    endpoints = express_prefix_files({
      "app.js"     => "const express = require('express'); const app = express(); app.use('/api', require('./sub'));",
      "sub.js"     => "const express = require('express'); const router = express.Router(); const child = express.Router(); const { register } = require('./helpers'); router.use(config.base + '/v1', child); register(child, '/leaf', (req, res) => res.send('ok')); module.exports = router;",
      "helpers.js" => "exports.register = function (router, path, handler) { router.get(path, handler); };",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/api/v1/leaf", {"prefix" => "unresolved"}}])
  end
end

describe "Express literal-derived prefix safety" do
  it "does not recover a new prefix from a truncated legacy constant" do
    endpoints = express_prefix_files({
      "app.js"   => "const express = require('express'); const app = express(); const base = '/api/' + runtime; app.use(base + '/v1', require('./child'));",
      "child.js" => "const express = require('express'); const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); module.exports = router;",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/leaf", {"prefix" => "unresolved"}}])
  end

  it "marks existing partial local prefixes without shrinking their URLs" do
    {"const base = '/api/' + runtime; app.use(base + '/v1', child);" => "/api//v1/leaf",
     "app.use('/a/' + id + '/b', child);"                            => "/a/leaf"}.each do |mount, expected|
      endpoints = express_prefix_files({
        "app.js" => "const express = require('express'); const app = express(); const child = express.Router(); #{mount} child.get('/leaf', (req, res) => res.send('ok'));",
      })
      endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{expected, {"prefix" => "unresolved"}}])
    end
  end
end

describe "Express helper binding scope ceiling" do
  it "does not apply one function's mount to another router with the same name" do
    endpoints = express_prefix_files({
      "app.js" => <<-JS,
        const express = require('express');
        const { register } = require('./helpers');
        function a(app) {
          const child = express.Router();
          app.use(config.base + '/a', child);
          register(child, '/one', (req, res) => res.send('ok'));
        }
        function b(app) {
          const child = express.Router();
          app.use(child);
          register(child, '/two', (req, res) => res.send('ok'));
        }
        JS
      "helpers.js" => "exports.register = function (router, path, handler) { router.get(path, handler); };",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.sort_by!(&.[0]).should eq([{"/one", nil}, {"/two", nil}])
  end
end

describe "Express helper reassignment ceiling" do
  it "does not transfer a previous router's prefix through a reassigned name" do
    endpoints = express_prefix_files({
      "app.js"     => "const express = require('express'); const app = express(); const { register } = require('./helpers'); let child = express.Router(); app.use(config.base + '/a', child); child = express.Router(); register(child, '/two', (req, res) => res.send('ok')); app.use(child);",
      "helpers.js" => "exports.register = function (router, path, handler) { router.get(path, handler); };",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/two", nil}])
  end
end

describe "Express prefix-only constant resolution" do
  it "does not enable new route-path resolution while reading a mount's imported constants" do
    endpoints = express_prefix_files({
      "app.js"   => "const express = require('express'); const app = express(); const { ROUTE } = require('./paths'); app.use(config.base, require('./child')); app.get(ROUTE, (req, res) => res.send('ok'));",
      "paths.js" => "const ROUTE = '/not-added'; module.exports = { ROUTE };",
      "child.js" => "const express = require('express'); const router = express.Router(); router.get('/leaf', (req, res) => res.send('ok')); module.exports = router;",
    })
    endpoints.map { |e| {e.url, e.resolution} }.uniq!.should eq([{"/leaf", {"prefix" => "unresolved"}}])
  end
end
