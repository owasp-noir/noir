require "spec"
require "../../../src/miniparsers/hapi_extractor_ts"

describe Noir::TreeSitterHapiExtractor do
  it "extracts a single object route with verb and path" do
    source = <<-JS
      server.route({
          method: 'GET',
          path: '/users',
          handler: (request, h) => []
      });
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/users"}])
  end

  it "extracts every route from an array-of-objects config" do
    source = <<-JS
      server.route([
          { method: 'POST', path: '/users', handler: (request, h) => {} },
          { method: 'DELETE', path: '/users/{id}', handler: (request, h) => {} }
      ]);
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/users"},
      {"DELETE", "/users/{id}"},
    ])
  end

  it "fans out an array of methods into one route per verb" do
    source = <<-JS
      server.route({
          method: ['PUT', 'PATCH'],
          path: '/users/{id}',
          handler: (request, h) => {}
      });
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.map(&.verb).sort!.should eq(["PATCH", "PUT"])
    routes.map(&.path).uniq!.should eq(["/users/{id}"])
  end

  it "fans out the wildcard method into the standard verb set" do
    source = <<-JS
      server.route({
          method: '*',
          path: '/health',
          handler: () => 'ok'
      });
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.map(&.verb).sort!.should eq(["DELETE", "GET", "PATCH", "POST", "PUT"])
  end

  it "ignores unknown HTTP method strings" do
    source = <<-JS
      server.route({
          method: 'FOOBAR',
          path: '/nope',
          handler: () => {}
      });
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.should be_empty
  end

  it "captures query, header, cookie and body signals from the handler" do
    source = <<-JS
      server.route({
          method: 'POST',
          path: '/users/{id}',
          handler: (request, h) => {
              const filter = request.query.filter;
              const trace = request.headers['x-trace'];
              const session = request.state.session;
              const data = request.payload;
              return request.params.id;
          }
      });
      JS

    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.size.should eq(1)
    route = routes.first
    route.query_params.should contain("filter")
    route.header_params.should contain("x-trace")
    route.cookie_params.should contain("session")
    route.has_body?.should be_true
    # `request.params.id` is the URL placeholder, not an extra param.
    route.query_params.should_not contain("id")
  end

  it "does not treat unrelated method calls as routes" do
    source = <<-JS
      server.start();
      logger.route('not a route');
      JS

    # `.route` with a bare string arg (not an object/array) emits nothing.
    routes = Noir::TreeSitterHapiExtractor.extract_routes(source)
    routes.should be_empty
  end
end
