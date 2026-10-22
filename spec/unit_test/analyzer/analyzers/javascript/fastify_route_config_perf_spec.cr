require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/fastify"

# The route({...}) and query() passes re-scanned the whole file for plugin
# prefixes, indexed it by char offset and checked the whole result array for
# every route: 5000 `fastify.route({...})` calls never finished in a minute.
describe "Fastify route config pass on a large file" do
  it "stays linear and keeps plugin prefixes" do
    n = 5000
    content = String.build do |io|
      io << "// café\nconst fastify = require('fastify')();\n"
      io << "fastify.register(async (api) => {\n"
      n.times { |i| io << "  api.route({ method: 'GET', url: '/r#{i}', handler: async (request) => request.query.q });\n" }
      io << "}, { prefix: '/v1' });\n"
    end
    temp_dir = File.tempname("noir_fastify_perf")
    begin
      Dir.mkdir_p(temp_dir)
      app = File.join(temp_dir, "app.js")
      File.write(app, content)
      locator = CodeLocator.instance
      locator.clear_all
      locator.register_file(app, content)
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])

      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Javascript::Fastify.new(options).analyze }
      elapsed.should be < 5.seconds
      endpoints.size.should eq(n)
      last = endpoints.find! { |e| e.url == "/v1/r#{n - 1}" }
      last.details.code_paths.first.line.should eq(n + 3)
      last.params.map(&.name).should eq(["q"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
