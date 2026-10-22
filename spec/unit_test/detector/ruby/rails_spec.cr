require "../../../spec_helper"
require "../../../../src/detector/detectors/ruby/*"

describe "Detect Ruby Rails" do
  options = create_test_options
  instance = Detector::Ruby::Rails.new options

  it "gemfile/single_quot" do
    instance.detect("Gemfile", "gem 'rails'").should be_true
  end
  it "gemfile/double_quot" do
    instance.detect("Gemfile", "gem \"rails\"").should be_true
  end
  it "gemfile/railties_single_quot" do
    instance.detect("Gemfile", "gem 'railties', '~> 8.0.0'").should be_true
  end
  it "gemfile/railties_double_quot" do
    instance.detect("Gemfile", "gem \"railties\", \"~> 8.0.0\"").should be_true
  end
  it "gemfile/no_rails_components" do
    instance.detect("Gemfile", "gem 'sinatra'\ngem 'rack'").should be_false
  end

  it "gemspec/add_dependency_rails" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.name = "spree_core"
        s.add_dependency 'rails', '>= 7.2', '< 8.2'
      end
      RUBY
    instance.detect("spree/core/spree_core.gemspec", contents).should be_true
  end

  it "gemspec/add_dependency_railties" do
    contents = <<-RUBY
      Gem::Specification.new do |spec|
        spec.add_dependency "railties", "~> 8.0.0"
      end
      RUBY
    instance.detect("foo.gemspec", contents).should be_true
  end

  it "gemspec/add_runtime_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_runtime_dependency 'rails', '~> 7.0'
      end
      RUBY
    instance.detect("legacy.gemspec", contents).should be_true
  end

  it "gemspec/no_rails_dependency" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency 'sinatra'
        s.add_dependency 'rack'
      end
      RUBY
    instance.detect("sinatra-thing.gemspec", contents).should be_false
  end

  it "gemspec/add_dependency parenthesized call form" do
    contents = <<-RUBY
      Gem::Specification.new do |s|
        s.add_dependency('railties', "~> 8.0")
      end
      RUBY
    instance.detect("engine.gemspec", contents).should be_true
  end

  it "gemfile/does not match jquery-rails" do
    instance.detect("Gemfile", "gem 'jquery-rails'\ngem 'sinatra'").should be_false
  end

  # The dependency declaration is the better marker, but it is only there when
  # the scan reaches the manifest. A `config/` directory, an engine whose
  # gemspec does not name the framework, or one service of a monorepo scanned
  # app-by-app all detect as nothing without these — and then the analyzer
  # never runs and every route the app declares is lost.
  it "routes/modern draw block" do
    contents = <<-RUBY
      Rails.application.routes.draw do
        get '/api/posts', to: 'posts#index'
        resources :comments, only: [:index, :show]
      end
      RUBY
    instance.detect("config/routes.rb", contents).should be_true
  end

  it "routes/pre-3.0 draw block" do
    contents = <<-RUBY
      Blog::Application.routes.draw do
        root to: 'posts#index'
      end
      RUBY
    instance.detect("config/routes.rb", contents).should be_true
  end

  it "config.ru/run Rails.application" do
    contents = <<-RUBY
      require_relative "config/environment"
      run Rails.application
      Rails.application.load_server
      RUBY
    instance.detect("config.ru", contents).should be_true
  end

  it "application.rb/Rails::Application subclass" do
    contents = <<-RUBY
      require_relative "boot"
      require "rails/all"

      module Blog
        class Application < Rails::Application
          config.load_defaults 8.0
        end
      end
      RUBY
    instance.detect("config/application.rb", contents).should be_true
  end

  it "ruby/an ordinary file is not a marker" do
    contents = <<-RUBY
      class PostsController < ApplicationController
        def index
          @posts = Post.all
        end
      end
      RUBY
    instance.detect("app/controllers/posts_controller.rb", contents).should be_false
  end

  it "ruby/another framework's routing block is not Rails" do
    contents = <<-RUBY
      Hanami.application.routes do
        get "/posts", to: "posts.index"
      end
      RUBY
    instance.detect("config/routes.rb", contents).should be_false
  end

  it "ruby/prose mentioning rails is not a marker" do
    contents = <<-RUBY
      # This gem works with Rails, Sinatra and Hanami applications.
      # See the rails/all guide for details.
      module Thing
      end
      RUBY
    instance.detect("lib/thing.rb", contents).should be_false
  end
end
