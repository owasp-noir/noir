require "spec"
require "../../../src/miniparsers/hapi_extractor_ts"

describe "Hapi handler request bindings" do
  it "reads the actual request argument of arrow and classic handlers" do
    source = <<-JS
      server.route([
        { method: 'GET', path: '/arrow', handler: req => req.query.term },
        { method: 'POST', path: '/classic', handler: function (r, h) {
          return [r.headers['x-token'], r.state.session, r.payload];
        } }
      ]);
      JS
    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.first.query_params.should eq(["term"])
    routes.last.header_params.should eq(["x-token"])
    routes.last.cookie_params.should eq(["session"])
    routes.last.has_body?.should be_true
  end

  it "unwraps typed request parameters" do
    source = "server.route({ method: 'GET', path: '/typed', handler: (req: Request, h: ResponseToolkit) => req.query.term });"
    Noir::TreeSitterHapiExtractor.extract_routes(source, path: "routes.ts").first.query_params.should eq(["term"])
  end

  it "preserves a defaulted request argument" do
    source = "server.route({ method: 'GET', path: '/default', handler: (request = {}) => request.query.term });"
    Noir::TreeSitterHapiExtractor.extract_routes(source).first.query_params.should eq(["term"])
  end

  it "reports the request key rather than nested object members" do
    source = <<-JS
      server.route({ method: 'GET', path: '/nested', handler: (request, h) => [
        request.query.user.name, request.query['user'].id,
        request.headers['x-auth'].trim(), request.state.session.value
      ] });
      JS
    route = Noir::TreeSitterHapiExtractor.extract_routes(source).first
    route.query_params.should eq(["user"])
    route.header_params.should eq(["x-auth"])
    route.cookie_params.should eq(["session"])
  end

  it "accepts bracket access to the request category" do
    source = "server.route({ method: 'GET', path: '/brackets', handler: req => req['query']['term'] });"
    Noir::TreeSitterHapiExtractor.extract_routes(source).first.query_params.should eq(["term"])
  end

  it "does not read a different object named request as the handler input" do
    source = <<-JS
      server.route({ method: 'GET', path: '/local', handler: req => {
        const request = { query: { fake: 1 }, payload: {} };
        return [request.query.fake, request.payload, req.query.real];
      } });
      JS
    route = Noir::TreeSitterHapiExtractor.extract_routes(source).first
    route.query_params.should eq(["real"])
    route.has_body?.should be_false
  end

  it "keeps captured request reads but skips a nested function's shadowing argument" do
    source = <<-JS
      server.route({ method: 'GET', path: '/closures', handler: req => {
        const read = () => req.query.captured;
        const unrelated = (req) => req.query.fake;
        return [req.query.direct, read()];
      } });
      JS
    Noir::TreeSitterHapiExtractor.extract_routes(source).first.query_params.should eq(["captured", "direct"])
  end
end
