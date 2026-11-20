require "spec"
require "../../../src/miniparsers/elysia_extractor_ts"

describe "Elysia route argument positions" do
  it "does not promote a literal response to a path when the path is unresolved" do
    source = "new Elysia().get(runtimePath, '/phantom').post(otherPath, `/also-phantom`);"
    Noir::TreeSitterElysiaExtractor.extract_routes(source).should be_empty
  end

  it "keeps literal responses and reads only the second argument as the handler" do
    source = <<-JS
      new Elysia()
        .get('/static', 'hello')
        .get('/options', 'ok', () => query.not_a_handler)
        .get('/dynamic', (ctx) => ctx.query.real);
      JS
    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.map(&.path).sort!.should eq(["/dynamic", "/options", "/static"])
    routes.find! { |r| r.path == "/options" }.query_params.should be_empty
    routes.find! { |r| r.path == "/dynamic" }.query_params.should eq(["real"])
  end

  it "reads ordinary and generator function handlers" do
    source = <<-JS
      new Elysia()
        .get('/ordinary', function ({ query, headers }) { return [query.term, headers['x-token']]; })
        .post('/stream', async function* ({ body, cookie }) { yield [body, cookie.session]; });
      JS
    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    ordinary = routes.find! { |r| r.path == "/ordinary" }
    ordinary.query_params.should eq(["term"])
    ordinary.header_params.should eq(["x-token"])
    stream = routes.find! { |r| r.path == "/stream" }
    stream.cookie_params.should eq(["session"])
    stream.has_body?.should be_true
  end

  it "skips comments and unwraps typed path and handler arguments" do
    source = <<-TS
      new Elysia().get(/* path */ ('/typed' as const), /* handler */ (function (ctx: Context) {
        return ctx.query.term;
      }) as Handler);
      TS
    route = Noir::TreeSitterElysiaExtractor.extract_routes(source, path: "routes.ts").first
    route.path.should eq("/typed")
    route.query_params.should eq(["term"])
  end
end
