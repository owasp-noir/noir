require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Analyzers are handed every file in the scan, so a framework whose only
# anchor is a common directory or filename can claim a neighbouring project's
# routes. That never shows up in a single-framework fixture — it needs two
# projects in one scan, which is what a monorepo actually looks like.
private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.clear("file_map")
end

private def tech_sources(endpoints : Array(Endpoint), technology : String) : Array(String)
  endpoints.compact_map do |endpoint|
    next unless endpoint.details.technology == technology
    endpoint.details.code_paths.first?.try(&.path)
  end.uniq!
end

describe "analyzer project scoping" do
  it "keeps Nitro off another JS project's routes/ directory" do
    # `routes/` is the conventional router directory in Koa, Express and
    # Fastify too. Nitro used to claim every `*/routes/*.ts` in the scan, and
    # since a bare file names no method it emitted seven endpoints per file —
    # 42 phantom endpoints out of the Koa fixture alone.
    root = File.tempname("noir-nitro-scope")

    begin
      FileUtils.mkdir_p(File.join(root, "site", "routes"))
      File.write(File.join(root, "site", "nitro.config.ts"), "export default defineNitroConfig({})\n")
      File.write(File.join(root, "site", "routes", "hello.ts"), "export default defineEventHandler(() => 'hi')\n")

      FileUtils.mkdir_p(File.join(root, "api", "routes"))
      File.write(File.join(root, "api", "package.json"), %({"dependencies": {"koa": "^2.0.0", "koa-router": "^12.0.0"}}))
      File.write(File.join(root, "api", "index.js"), <<-JS)
        const Koa = require('koa');
        const Router = require('koa-router');
        const app = new Koa();
        const router = new Router();
        require('./routes/users')(router);
        app.use(router.routes());
        JS
      File.write(File.join(root, "api", "routes", "users.js"), <<-JS)
        module.exports = (router) => {
          router.get('/users', (ctx) => { ctx.body = []; });
        };
        JS

      endpoints = scan_tree(root)
      sources = tech_sources(endpoints, "js_nitro")
      sources.any?(&.includes?("/site/routes/hello.ts")).should be_true
      sources.any?(&.includes?("/api/routes/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "keeps Hanami and Rails off each other's config/routes.rb" do
    # Both frameworks anchor on `config/routes.rb`, so each parsed the other's
    # route table with its own DSL.
    root = File.tempname("noir-ruby-routes-scope")

    begin
      FileUtils.mkdir_p(File.join(root, "shop", "config"))
      File.write(File.join(root, "shop", "Gemfile"), "gem 'rails'\n")
      File.write(File.join(root, "shop", "config", "routes.rb"), <<-RUBY)
        Rails.application.routes.draw do
          get '/orders', to: 'orders#index'
        end
        RUBY

      FileUtils.mkdir_p(File.join(root, "admin", "config"))
      File.write(File.join(root, "admin", "Gemfile"), "gem 'hanami'\n")
      File.write(File.join(root, "admin", "config", "routes.rb"), <<-RUBY)
        module Admin
          class Routes < Hanami::Routes
            get "/books", to: "books.index"
          end
        end
        RUBY

      endpoints = scan_tree(root)

      hanami_sources = tech_sources(endpoints, "ruby_hanami")
      hanami_sources.any?(&.includes?("/admin/config/routes.rb")).should be_true
      hanami_sources.any?(&.includes?("/shop/")).should be_false

      rails_sources = tech_sources(endpoints, "ruby_rails")
      rails_sources.any?(&.includes?("/shop/config/routes.rb")).should be_true
      rails_sources.any?(&.includes?("/admin/config/routes.rb")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
