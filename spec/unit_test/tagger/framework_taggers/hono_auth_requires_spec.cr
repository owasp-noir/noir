require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "../../../../src/analyzer/analyzers/javascript/hono"

# Scans `source` as a one-file Hono project and runs the auth tagger, as a
# scan does.
private def hono_requires(source : String) : Hash(String, Tag?)
  dir = File.tempname("hono_requires")
  Dir.mkdir_p(dir)
  file = File.join(dir, "index.ts")
  File.write(file, source)
  CodeLocator.instance.clear_all
  CodeLocator.instance.register_path(file)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  endpoints = Analyzer::Javascript::Hono.new(options).analyze
  endpoints.map! do |row|
    details = row.details
    details.technology = "js_hono"
    row.details = details
    row
  end
  endpoints = HonoAuthTagger.new(options).perform(endpoints)
  endpoints.to_h { |row| {"#{row.method} #{row.url}", row.tags.find { |tag| tag.tagger == "hono_auth" }} }
ensure
  FileUtils.rm_rf(dir) if dir
end

private def requirement(tag : Tag?) : String?
  tag.try(&.requires).try do |clauses|
    clauses.map do |clause|
      atoms = clause.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }
      atoms.size > 1 ? "(#{atoms.join(" | ")})" : atoms[0]
    end.join(" & ")
  end
end

describe "HonoAuthTagger requires" do
  it "reads a hono/* guard among the route's middleware" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      import { bearerAuth } from 'hono/bearer-auth'
      const app = new Hono()
      const jwt = (options: any) => async (c: any, next: any) => next()
      app.get('/bearer', bearerAuth({ token: 't' }), (c) => c.json({}))
      app.get('/both', bearerAuth({ token: 't' }), requireAuth, (c) => c.json({}))
      app.get('/local', jwt({ secret: 's' }), (c) => c.json({}))
      TS
    requirement(tags["GET /bearer"]).should eq("authenticated")
    requirement(tags["GET /both"]).should eq("authenticated & unresolved:requireAuth")
    # `jwt` is the module's own function, not hono/jwt.
    tags["GET /local"].should_not be_nil
    requirement(tags["GET /local"]).should be_nil
  end

  it "does not lend one route's middleware to another route on the same line" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      import { bearerAuth } from 'hono/bearer-auth'
      const app = new Hono()
      app.get('/x', bearerAuth({ token: 't' }), (c) => c.json({})); app.get('/y', (c) => c.json({}))
      TS
    tags["GET /y"].should_not be_nil
    requirement(tags["GET /y"]).should be_nil
  end

  it "reads a use() above the route on its own receiver, and keeps the default for a tag from a use() scope" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      import { bearerAuth } from 'hono/bearer-auth'
      import { jwt } from 'hono/jwt'
      const app = new Hono()
      app.use('/admin/*', jwt({ secret: 's' }))
      app.get('/admin/a', bearerAuth({ token: 't' }), (c) => c.json({}))
      app.get('/admin/b', (c) => c.json({}))
      TS
    requirement(tags["GET /admin/a"]).should eq("authenticated")
    tags["GET /admin/b"].should_not be_nil
    requirement(tags["GET /admin/b"]).should be_nil
  end

  it "reads each element of a zod-openapi route's middleware" do
    tags = hono_requires(<<-TS)
      import { OpenAPIHono, createRoute } from '@hono/zod-openapi'
      import { bearerAuth } from 'hono/bearer-auth'
      const app = new OpenAPIHono()
      app.openapi(createRoute({ method: 'get', path: '/a', middleware: [bearerAuth({ token: 't' }), authMiddleware], responses: {} }), (c) => c.json({}))
      app.openapi(createRoute({ method: 'get', path: '/b', middleware: [authMiddleware], responses: {} }), (c) => c.json({}))
      TS
    requirement(tags["GET /a"]).should eq("authenticated & unresolved:authMiddleware")
    tags["GET /b"].should_not be_nil
    requirement(tags["GET /b"]).should be_nil
  end

  it "keeps every unread middleware and every use() that may cover the route" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      import { cors } from 'hono/cors'
      import { jwt } from 'hono/jwt'
      import { bearerAuth } from 'hono/bearer-auth'
      import { requireRole } from './roles'
      const app = new Hono()
      const api = new Hono()
      app.get('/role', jwt({ secret: 's' }), requireRole('admin'), (c) => c.json({}))
      app.get('/inline', jwt({ secret: 's' }), async (c, next) => { if (c.get('jwtPayload').role !== 'admin') return c.text('no', 403); await next() }, (c) => c.json({}))
      app.get('/quiet', cors(), async (c, next) => { c.set('at', Date.now()); await next() }, jwt({ secret: 's' }), (c) => c.json({}))
      TS
    requirement(tags["GET /role"]).should eq("authenticated & unresolved:requireRole('admin')")
    requirement(tags["GET /inline"]).should eq("authenticated & unresolved:async (c, next) => { if (c.get('jwtPayload').role !== 'admin') return c.text('no', 403); await next() }")
    requirement(tags["GET /quiet"]).should eq("authenticated")
  end

  it "keeps a use() on any receiver of the file that may cover the route" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      import { bearerAuth } from 'hono/bearer-auth'
      const app = new Hono()
      const api = new Hono()
      api.use('*', checkAdmin)
      api.get('/x', bearerAuth({ token: 't' }), (c) => c.json({}))
      app.route('/api', api)
      app.use('/api/*', async (c, next) => { if (!c.req.header('x')) return c.text('no', 403); await next() })
      TS
    requirement(tags["GET /api/x"]).should eq("authenticated & unresolved:checkAdmin & unresolved:async (c, next) => { if (!c.req.header('x')) return c.text('no', 403); await next() }")
  end

  it "binds no package through a commented-out import" do
    tags = hono_requires(<<-TS)
      import { Hono } from 'hono'
      // import { bearerAuth } from 'hono/bearer-auth'
      const bearerAuth = (o: any) => async (c: any, next: any) => next()
      const app = new Hono()
      app.get('/x', bearerAuth({ token: 't' }), (c) => c.json({}))
      TS
    tags["GET /x"].should_not be_nil
    requirement(tags["GET /x"]).should be_nil
  end
end
