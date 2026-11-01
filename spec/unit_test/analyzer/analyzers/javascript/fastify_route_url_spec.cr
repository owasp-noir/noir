require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/fastify"

private def with_fastify_file(content : String, &)
  dir = File.tempname("fastify_url_spec")
  Dir.mkdir_p(dir)
  path = File.join(dir, "app.js")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear_all
  locator.register_file(path, content)
  begin
    yield path
  ensure
    locator.clear_all
    FileUtils.rm_rf(dir)
  end
end

describe "Fastify route url handling" do
  options = create_test_options

  it "accepts string literals and template literals without substitutions" do
    content = <<-JS
      const fastify = require('fastify')();
      fastify.route({ method: 'GET', url: '/literal', handler: async () => ({}) });
      fastify.route({ method: 'POST', url: `/template_clean`, handler: async () => ({}) });
      JS
    with_fastify_file(content) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      endpoints = Analyzer::Javascript::Fastify.new(opts).analyze
      endpoints.map(&.url).sort!.should eq(["/literal", "/template_clean"])
    end
  end

  it "extracts leading string literal for binary expressions and skips dynamic expressions" do
    content = <<-JS
      const fastify = require('fastify')();
      const dynamicUrl = "/dynamic";
      fastify.route({ method: 'GET', url: '/' + 'x', handler: async () => ({}) });
      fastify.route({ method: 'GET', url: '/users/' + id, handler: async () => ({}) });
      fastify.route({ method: 'GET', url: dynamicUrl, handler: async () => ({}) });
      fastify.route({ method: 'GET', url: dynamicUrl + '/tail', handler: async () => ({}) });
      fastify.route({ method: 'GET', url: `/template/${id}`, handler: async () => ({}) });
      JS
    with_fastify_file(content) do |path|
      opts = options.dup
      opts["base"] = YAML::Any.new([YAML::Any.new(File.dirname(path))])
      endpoints = Analyzer::Javascript::Fastify.new(opts).analyze
      endpoints.map(&.url).sort!.should eq(["/", "/users/"])
    end
  end
end
