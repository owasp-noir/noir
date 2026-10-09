require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/hono"

private def hono_endpoints(source : String) : Array(Endpoint)
  temp_dir = File.tempname("noir_hono_on")
  Dir.mkdir_p(temp_dir)
  app = File.join(temp_dir, "app.ts")
  File.write(app, source)
  locator = CodeLocator.instance
  locator.clear_all
  locator.register_file(app, source)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  options["include_callee"] = YAML::Any.new(true)
  Analyzer::Javascript::Hono.new(options).analyze
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "Hono app.on routes" do
  source = <<-TS
    import { Hono } from 'hono'
    const app = new Hono()
    app.get('/a', (c) => c.text('a'))
    app.get('/b', (c) => c.text('b'))
    app.get('/c', (c) => c.text('c'))
    app.get('/d', (c) => c.text('d'))
    app.get('/e', (c) => c.text('e'))
    app.get('/f', (c) => c.text('f'))
    app.get('/g', (c) => c.text('g'))
    app.get('/h', (c) => c.text('h'))
    app.get('/i', (c) => c.text('i'))
    app.get('/j', (c) => c.text('j'))

    app.on(['GET', 'QUERY'], '/items/search', async (c) => {
      const filter = c.req.query('filter')
      return c.json({ items: [] })
    })

    app.query('/search', async (c) => {
      return c.json(await c.req.json())
    })
    TS

  # The line walk summed `line.bytesize + 1` over CRLF-stripped lines, so the
  # offset handed to the callee lookup drifted a byte per CRLF line.
  it "keeps app.on() callees and lines with CRLF line endings" do
    lf = hono_endpoints(source)
    crlf = hono_endpoints(source.gsub("\n", "\r\n"))
    summary = ->(eps : Array(Endpoint)) {
      eps.map { |e| "#{e.method} #{e.url} #{e.details.code_paths.first.line} #{e.callees.map(&.name)}" }.sort!
    }
    summary.call(crlf).should eq(summary.call(lf))
    search = crlf.find! { |e| e.method == "QUERY" && e.url == "/items/search" }
    search.details.code_paths.first.line.should eq(14)
    search.callees.map(&.name).should eq(["c.req.query", "c.json"])
  end

  # Each route used to be checked against the whole result array, char
  # offsets and all: 5000 app.on() routes in one file took ~40s.
  it "stays linear on a large app.on() file" do
    n = 5000
    big = String.build do |io|
      io << "// café\nimport { Hono } from 'hono'\nconst app = new Hono()\n"
      n.times { |i| io << "app.on('GET', '/r#{i}', (c) => c.text(c.req.query('q')))\n" }
    end
    endpoints = [] of Endpoint
    elapsed = Time.measure { endpoints = hono_endpoints(big) }
    elapsed.should be < 5.seconds
    endpoints.size.should eq(n)
  end

  it "reads on() on any app but not on event emitters or non-path names" do
    eps = hono_endpoints(<<-TS)
      import { Hono } from 'hono'
      const books = new Hono()
      books.on('GET', '/books-on', (c) => c.json({}))
      ee.on('get', 'cache-key', (v) => {})
      socket.on('delete', '/room/1', () => {})
      myEmitter.on('options', '/ignored', cb)
      cache.on(['get', 'set'], 'key', cb)
      proxy.on('head', '/x', handler)
      TS
    eps.map { |e| "#{e.method} #{e.url}" }.should eq(["GET /books-on"])
  end

  it "attaches callees to app.query() routes" do
    route = hono_endpoints(source).find! { |e| e.url == "/search" }
    route.callees.map(&.name).should contain("c.req.json")
  end
end
