require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/analyzer/analyzers/ruby/sinatra"
require "file_utils"

# Rails, Hanami and Sinatra all spell a route `get "/books" …`, and every Ruby
# analyzer is handed every `.rb` file in the scan. These predicates are what
# let an analyzer step aside from a router that is unmistakably another
# framework's.
class RubyRouterHarness < Analyzer::Ruby::Sinatra
  def rails?(source : String) : Bool
    rails_router_source?(source)
  end

  def hanami?(source : String) : Bool
    hanami_router_source?(source)
  end
end

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

private def write_shard_project(dir : String, name : String, shard : String, repo : String, source : String)
  FileUtils.mkdir_p(File.join(dir, "src"))
  File.write(File.join(dir, "shard.yml"), <<-YAML)
    name: #{name}
    version: 0.1.0
    targets:
      #{name}:
        main: src/#{name}.cr
    dependencies:
      #{shard}:
        github: #{repo}
    YAML
  File.write(File.join(dir, "src", "#{name}.cr"), source)
end

describe "analyzer project scoping (crystal, ruby)" do
  it "tells Kemal, Grip and Lucky apart by their shard manifest" do
    # `get "/path"` is the same line in all three. Nothing in the source can
    # separate them; `shard.yml` can.
    root = File.tempname("noir-crystal-shard-scope")

    begin
      write_shard_project(File.join(root, "edge"), "edge", "kemal", "kemalcr/kemal", <<-CRYSTAL)
        require "kemal"

        get "/edge/health" do
          "ok"
        end
        CRYSTAL

      write_shard_project(File.join(root, "api"), "api", "grip", "grip-framework/grip", <<-CRYSTAL)
        require "grip"

        class Application < Grip::Application
          def initialize
            get "/api/status", StatusController
          end
        end
        CRYSTAL

      endpoints = scan_tree(root)

      kemal_sources = tech_sources(endpoints, "crystal_kemal")
      kemal_sources.any?(&.includes?("/edge/")).should be_true
      kemal_sources.any?(&.includes?("/api/")).should be_false

      grip_sources = tech_sources(endpoints, "crystal_grip")
      grip_sources.any?(&.includes?("/api/")).should be_true
      grip_sources.any?(&.includes?("/edge/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "falls back to scanning everything when no shard.yml declares the framework" do
    # A source tree checked out without its manifest must behave exactly as it
    # did before the gate existed.
    root = File.tempname("noir-crystal-no-shard")

    begin
      write_shard_project(root, "edge", "kemal", "kemalcr/kemal", <<-CRYSTAL)
        require "kemal"

        get "/edge/health" do
          "ok"
        end
        CRYSTAL
      File.delete(File.join(root, "shard.yml"))

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      options["techs"] = YAML::Any.new("crystal_kemal")
      runner = NoirRunner.new(options)
      runner.detect
      runner.analyze
      runner.endpoints.map(&.url).should contain("/edge/health")
      CodeLocator.instance.clear("file_map")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  it "recognizes a Rails or Hanami router so Sinatra can step aside" do
    # Sinatra has no `config/routes.rb` convention, so a file that is
    # unmistakably one of theirs is never also a Sinatra app. Pre-fix Sinatra
    # parsed both route tables with its own DSL, interpolations and all
    # (`GET /#{ENV.fetch(` out of a Rails routes.rb).
    harness = RubyRouterHarness.new(create_test_options)

    rails_routes = <<-'RUBY'
      Rails.application.routes.draw do
        get "/#{ENV.fetch('URL_COMPONENT', 'bb')}/:area" => "billboards#show"
        resources :posts
      end
      RUBY
    harness.rails?(rails_routes).should be_true
    harness.hanami?(rails_routes).should be_false

    hanami_routes = <<-RUBY
      module Admin
        class Routes < Hanami::Routes
          get "/books", to: "books.index"
        end
      end
      RUBY
    harness.hanami?(hanami_routes).should be_true
    harness.rails?(hanami_routes).should be_false

    # A plain Sinatra app is neither, so nothing steps aside for it.
    sinatra_app = <<-RUBY
      require 'sinatra'

      get '/tools/ping' do
        'pong'
      end
      RUBY
    harness.rails?(sinatra_app).should be_false
    harness.hanami?(sinatra_app).should be_false
  end

  it "keeps Sinatra off a Rails route table end to end" do
    root = File.tempname("noir-sinatra-scope")

    begin
      sinatra_dir = File.join(root, "tools")
      FileUtils.mkdir_p(sinatra_dir)
      File.write(File.join(sinatra_dir, "Gemfile"), "gem 'sinatra'\n")
      File.write(File.join(sinatra_dir, "app.rb"), <<-RUBY)
        require 'sinatra'

        get '/tools/ping' do
          'pong'
        end
        RUBY

      rails_dir = File.join(root, "shop", "config")
      FileUtils.mkdir_p(rails_dir)
      File.write(File.join(root, "shop", "Gemfile"), "gem 'rails'\n")
      File.write(File.join(rails_dir, "routes.rb"), <<-RUBY)
        Rails.application.routes.draw do
          get '/orders', to: 'orders#index'
        end
        RUBY

      endpoints = scan_tree(root)
      sinatra_sources = tech_sources(endpoints, "ruby_sinatra")
      sinatra_sources.any?(&.includes?("/tools/app.rb")).should be_true
      sinatra_sources.any?(&.includes?("/shop/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
