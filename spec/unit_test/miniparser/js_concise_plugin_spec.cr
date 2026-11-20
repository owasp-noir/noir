require "../../spec_helper"
require "../../../src/miniparsers/js_route_extractor"

private def concise_plugin_routes(source : String, suffix : String = ".js") : Array(Endpoint)
  file = File.tempfile("noir-concise-plugin", suffix, &.print(source))
  CodeLocator.instance.clear_all
  CodeLocator.instance.register_file(file.path, source)
  Noir::JSRouteExtractor.extract_routes(file.path, source)
ensure
  file.try &.delete
  CodeLocator.instance.clear_all
end

describe "JavaScript concise plugin function ranges" do
  it "keeps concise and block plugins under their own prefixes" do
    source = <<-JS
      const Fastify = require('fastify');
      const app = Fastify();
      const handler = async (req, reply) => reply.send(req.query.term);
      const concise = async (router) => void router.get('/one', handler);
      async function block(router) { router.get('/two', handler); }
      app.register(concise, {prefix: '/a'});
      app.register(block, {prefix: '/b'});
      JS
    routes = concise_plugin_routes(source)
    routes.map(&.url).sort!.should eq(["/a/one", "/b/two"])
    route = routes.find! { |ep| ep.url == "/a/one" }
    route.details.code_paths.first.line.should eq(4)
    route.params.map { |param| {param.name, param.param_type} }.should eq([{"term", "query"}])
  end

  it "does not use the registration options object as a concise function body" do
    source = <<-JS
      const app = require('fastify')();
      const plugin = async router => void router.get('/leaf', async () => 'ok');
      app.register(plugin, {prefix: '/api'});
      JS
    concise_plugin_routes(source).map(&.url).should eq(["/api/leaf"])
  end

  it "reads multiline typed and wrapped arrow functions" do
    source = <<-TS
      import Fastify from 'fastify';
      const app = Fastify();
      const plugin: FastifyPluginAsync = (async (router: FastifyInstance): Promise<void> =>
        void router.get('/typed', async () => 'ok')) satisfies FastifyPluginAsync;
      app.register(plugin, {prefix: '/v1'});
      TS
    routes = concise_plugin_routes(source, ".ts")
    routes.map(&.url).should eq(["/v1/typed"])
    routes.first.details.code_paths.first.line.should eq(4)
  end

  it "retains every prefix when a concise plugin is mounted twice" do
    source = <<-JS
      const app = require('fastify')();
      const plugin = async router => void router.get('/leaf', async () => 'ok');
      app.register(plugin, {prefix: '/one'});
      app.register(plugin, {prefix: '/two'});
      JS
    concise_plugin_routes(source).map(&.url).sort!.should eq(["/one/leaf", "/two/leaf"])
  end

  it "keeps the scope of a block arrow with a TypeScript object return type" do
    source = <<-TS
      import Fastify from 'fastify';
      const app = Fastify();
      const plugin = (router: FastifyInstance, opts: object, done: () => void): { done: boolean } => {
        router.get('/typed', async () => 'ok');
        done();
        return {done: true};
      };
      app.register(plugin, {prefix: '/api'});
      TS
    concise_plugin_routes(source, ".ts").map(&.url).should eq(["/api/typed"])
  end

  it "preserves unrelated routes if the optional AST pass times out" do
    source = String.build do |io|
      io << "const app = require('fastify')();\nconst unused = value => value;\n"
      io << "const plugin = async router => { router.get('/scoped', async () => 'ok'); };\n"
      1000.times { |i| io << "const n#{i} = #{i};\n" }
      io << "app.register(plugin, {prefix: '/api'});\napp.get('/keep', async () => 'ok');\n"
    end
    previous = Noir::TreeSitter.parse_timeout_micros
    Noir::TreeSitter.parse_timeout_micros = 1_u64
    expect_raises(Exception, /timed out/) do
      Noir::TreeSitter.parse_js_family(source, "routes.js") { |root| root }
    end
    concise_plugin_routes(source).map(&.url).sort!.should eq(["/api/scoped", "/keep"])
  ensure
    Noir::TreeSitter.parse_timeout_micros = previous if previous
  end
end
