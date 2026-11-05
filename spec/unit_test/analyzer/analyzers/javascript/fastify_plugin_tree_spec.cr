require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/fastify"
require "../../../../../src/analyzer/analyzers/javascript/restify"

private def fastify_urls(files : Hash(String, String), analyzer = Analyzer::Javascript::Fastify) : Array(String)
  dir = File.tempname("fastify_tree_spec")
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
    # The analyzer leaves de-duplication to the optimizer.
    analyzer.new(options).analyze.map { |e| "#{e.method} #{e.url}" }.uniq!.sort!
  ensure
    locator.clear_all
    FileUtils.rm_rf(dir)
  end
end

private def plugin(body : String) : String
  "module.exports = async function (app) {\n#{body}\n}\n"
end

# N layers of two files, each registering both files of the next layer
# without a prefix: 2^N paths to the last layer.
private def layered_app(layers : Int32) : Hash(String, String)
  files = {"app.js" => "const fastify = require('fastify')()\nfastify.register(require('./l0a'))\nfastify.register(require('./l0b'))\n"}
  layers.times do |i|
    nxt = i + 1 < layers ? "  app.register(require('./l#{i + 1}a'))\n  app.register(require('./l#{i + 1}b'))\n" : ""
    {"a", "b"}.each { |s| files["l#{i}#{s}.js"] = plugin("#{nxt}  app.get('/l#{i}#{s}', async () => 1)") }
  end
  files
end

describe "Fastify cross-file plugin tree" do
  it "keeps the root URL of a plugin also registered inside a prefixed plugin" do
    fastify_urls({
      "app.js"    => "const fastify = require('fastify')()\nfastify.register(require('./health'))\nfastify.register(require('./api'), { prefix: '/api' })\n",
      "api.js"    => plugin("  app.register(require('./health'))\n  app.get('/items', async () => [])"),
      "health.js" => plugin("  app.get('/health', async () => 'ok')"),
    }).should eq(["GET /api/health", "GET /api/items", "GET /health"])
  end

  it "keeps the root URL of a plugin registered unprefixed and prefixed from one file" do
    fastify_urls({
      "app.js"    => "const fastify = require('fastify')()\nfastify.register(require('./health'))\nfastify.register(require('./health'), { prefix: '/v1' })\n",
      "health.js" => plugin("  app.get('/health', async () => 'ok')"),
    }).should eq(["GET /health", "GET /v1/health"])
  end

  it "serves named exports of one module mounted under the same prefix under it" do
    fastify_urls({
      "app.js"    => "const fastify = require('fastify')()\nconst routes = require('./routes')\nfastify.register(routes.users, { prefix: '/a' })\nfastify.register(routes.admin, { prefix: '/a' })\nfastify.register(require('./api'), { prefix: '/api' })\n",
      "api.js"    => "const routes = require('./routes')\n" + plugin("  app.register(routes.billing)\n  app.register(routes.reports)\n  app.register(routes.users, { prefix: '/b' })\n  app.register(routes.admin, { prefix: '/b' })"),
      "routes.js" => "async function users (app) { app.get('/users', async () => 1) }\nasync function admin (app) { app.get('/admin', async () => 1) }\nasync function billing (app) { app.get('/billing', async () => 1) }\nasync function reports (app) { app.get('/reports', async () => 1) }\nmodule.exports = { users, admin, billing, reports }\n",
    }).should eq(["GET /a/admin", "GET /a/users", "GET /api/b/admin", "GET /api/b/users", "GET /api/billing", "GET /api/reports"])
  end

  it "serves Restify routers of one module applied under the same prefix under it" do
    fastify_urls({
      "server.js"  => "const restify = require('restify')\nconst routers = require('./routers')\nconst server = restify.createServer()\nrouters.users.applyRoutes(server, '/a')\nrouters.admin.applyRoutes(server, '/a')\n",
      "routers.js" => "const Router = require('restify-router').Router\nconst users = new Router()\nusers.get('/users', (req, res, next) => next())\nconst admin = new Router()\nadmin.get('/admin', (req, res, next) => next())\nmodule.exports = { users, admin }\n",
    }, Analyzer::Javascript::Restify).should eq(["GET /a/admin", "GET /a/users"])
  end

  it "reads an empty prefix as no prefix and a 'prefix' string value as no prefix key" do
    fastify_urls({
      "app.js"   => "const fastify = require('fastify')()\nfastify.register(require('./api'), { prefix: '/api' })\n",
      "api.js"   => plugin("  app.register(require('./empty'), { prefix: '' })\n  app.register(require('./redis'), { namespace: 'prefix' })\n  app.register(require('./dyn'), { prefix: base })"),
      "empty.js" => plugin("  app.get('/empty', async () => 1)"),
      "redis.js" => plugin("  app.get('/redis', async () => 1)"),
      "dyn.js"   => plugin("  app.get('/dyn', async () => 1)"),
    }).should eq(["GET /api/empty", "GET /api/redis", "GET /dyn"])
  end

  it "serves a directory autoloaded under two prefixes under both" do
    fastify_urls({
      "app.js" => <<-JS,
        const path = require('path')
        const AutoLoad = require('@fastify/autoload')
        module.exports = async function (fastify, opts) {
          fastify.register(AutoLoad, { dir: path.join(__dirname, 'routes'), options: { prefix: '/v1' } })
          fastify.register(AutoLoad, { dir: path.join(__dirname, 'routes'), options: { prefix: '/v2' } })
        }
        JS
      "routes/users/index.js" => "module.exports = async function (f) { f.get('/list', async (req) => req.query.q) }\n",
    }).should eq(["GET /v1/users/list", "GET /v2/users/list"])
  end

  it "walks plugins registered from several parents in linear time" do
    small = Time.measure { fastify_urls(layered_app(12)).size.should eq(24) }
    large = Time.measure { fastify_urls(layered_app(24)).size.should eq(48) }
    # Walking every path took 2^N: 4096 times longer here, not 2-3.
    (large / small).should be < 16
  end
end
