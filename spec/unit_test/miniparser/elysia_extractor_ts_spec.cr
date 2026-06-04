require "spec"
require "../../../src/miniparsers/elysia_extractor_ts"

describe Noir::TreeSitterElysiaExtractor do
  it "extracts chained verb routes" do
    source = <<-TS
      const app = new Elysia()
          .get('/users', () => [])
          .post('/users', ({ body }) => body)
          .listen(3000)
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/users"},
      {"POST", "/users"},
    ].sort)
  end

  it "joins group prefixes onto inner routes" do
    source = <<-TS
      const app = new Elysia()
          .group('/api/v1', (app) =>
              app
                  .get('/health', () => 'ok')
                  .post('/submit', ({ body }) => body)
          )
          .listen(3000)
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/api/v1/health"},
      {"POST", "/api/v1/submit"},
    ].sort)
  end

  it "fans out the .all verb into the standard verb set" do
    source = <<-TS
      const app = new Elysia()
          .all('/any', () => 'ok')
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.select { |r| r.path == "/any" }.map(&.verb).sort!.should eq(
      ["DELETE", "GET", "PATCH", "POST", "PUT"]
    )
  end

  it "marks a body param from the destructured handler signature" do
    source = <<-TS
      const app = new Elysia()
          .post('/submit', ({ body }) => body)
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.first.has_body?.should be_true
  end

  it "captures query, header and cookie signals from handler bodies" do
    source = <<-TS
      const app = new Elysia()
          .get('/search', ({ query }) => {
              const filter = query.filter
              return filter
          })
          .get('/trace', ({ headers }) => {
              const token = headers['x-token']
              return token
          })
          .delete('/sessions/:id', ({ params, cookie }) => {
              const session = cookie.session
              return params.id
          })
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    search = routes.find! { |r| r.path == "/search" }
    trace = routes.find! { |r| r.path == "/trace" }
    sessions = routes.find! { |r| r.path == "/sessions/:id" }

    search.query_params.should contain("filter")
    trace.header_params.should contain("x-token")
    sessions.cookie_params.should contain("session")
    # `params.id` maps to the URL placeholder, not a query param.
    sessions.query_params.should be_empty
  end

  it "descends through transparent .guard and .use wrappers" do
    source = <<-TS
      const app = new Elysia()
          .guard({ beforeHandle: auth }, (app) =>
              app.get('/protected', () => 'secret')
          )
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/protected"}])
  end

  it "deduplicates repeated param signals" do
    source = <<-TS
      const app = new Elysia()
          .get('/dup', ({ query }) => {
              const a = query.filter
              const b = query.filter
              return a
          })
      TS

    routes = Noir::TreeSitterElysiaExtractor.extract_routes(source)
    routes.first.query_params.should eq(["filter"])
  end
end
