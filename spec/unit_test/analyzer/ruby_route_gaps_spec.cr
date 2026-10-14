require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Ruby routing shapes that real apps use and the analyzers used to miss.
# Each example scans a throwaway tree end to end, so detection, analysis
# and optimization all run as they do from the CLI.
private def scan_ruby_tree(files : Hash(String, String)) : Array(Endpoint)
  root = File.tempname("noir-ruby-route-gaps")
  files.each do |rel, body|
    path = File.join(root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(root) if root
end

private def find_ep(endpoints : Array(Endpoint), method : String, url : String) : Endpoint
  endpoints.find { |e| e.method == method && e.url == url } ||
    fail "missing #{method} #{url} in #{endpoints.map { |e| "#{e.method} #{e.url}" }}"
end

private def param_names(endpoint : Endpoint, type : String) : Array(String)
  endpoint.params.select(&.param_type.==(type)).map(&.name).sort!
end

RAILS_GEMFILE = %(source "https://rubygems.org"\ngem "rails"\n)

describe "Ruby route gaps" do
  it "reads Rails 8 params.expect as strong params" do
    endpoints = scan_ruby_tree({
      "Gemfile"                                => RAILS_GEMFILE,
      "config/routes.rb"                       => "Rails.application.routes.draw do\n  resources :products\nend\n",
      "app/controllers/products_controller.rb" => <<-RUBY,
        class ProductsController < ApplicationController
          def create
            @product = Product.new(product_params)
          end

          def update
            @product.update(params.expect(product: [[ :sku ]]))
          end

          private
            def product_params
              params.expect(product: [ :name, :price, tags: [] ])
            end
        end
        RUBY
    })

    param_names(find_ep(endpoints, "POST", "/products"), "form").should eq(%w[name price tags])
    param_names(find_ep(endpoints, "PATCH", "/products/1"), "form").should eq(%w[sku])
  end

  it "gives shallow-nested Rails resources unnested member routes" do
    controller = "class CommentsController < ApplicationController\n  def index; end\n  def create; end\n  def show; end\n  def destroy; end\nend\n"
    endpoints = scan_ruby_tree({
      "Gemfile"          => RAILS_GEMFILE,
      "config/routes.rb" => <<-RUBY,
      Rails.application.routes.draw do
        resources :posts, shallow: true do
          resources :comments do
            member do
              post :approve
            end
          end
        end
        namespace :admin do
          shallow do
            resources :posts do
              resources :comments
            end
          end
        end
      end
      RUBY
      "app/controllers/comments_controller.rb"       => controller,
      "app/controllers/admin/comments_controller.rb" => controller,
    })
    urls = endpoints.map { |e| "#{e.method} #{e.url}" }

    urls.should contain("GET /posts/1/comments")
    urls.should contain("POST /posts/1/comments")
    urls.should contain("GET /comments/1")
    urls.should contain("DELETE /comments/1")
    urls.should contain("POST /comments/1/approve")
    urls.should contain("GET /admin/posts/1/comments")
    urls.should contain("GET /admin/comments/1")
    urls.should_not contain("GET /posts/1/comments/1")
    urls.should_not contain("GET /admin/posts/1/comments/1")
  end

  it "routes symbol verbs inside a Rails controller block to that controller" do
    endpoints = scan_ruby_tree({
      "Gemfile"          => RAILS_GEMFILE,
      "config/routes.rb" => <<-RUBY,
      Rails.application.routes.draw do
        controller :static do
          get :privacy
          get :terms
        end
        scope controller: :pages do
          get :about
        end
      end
      RUBY
      "app/controllers/pages_controller.rb" => "class PagesController < ApplicationController\n  def about\n    params[:lang]\n  end\nend\n",
    })

    find_ep(endpoints, "GET", "/privacy")
    find_ep(endpoints, "GET", "/terms")
    param_names(find_ep(endpoints, "GET", "/about"), "query").should eq(%w[lang])
  end

  it "keeps Grape mount paths and types declared GET params as query" do
    endpoints = scan_ruby_tree({
      "Gemfile"         => %(source "https://rubygems.org"\ngem "grape"\n),
      "app/api/root.rb" => <<-RUBY,
       module API
         class Root < Grape::API
           prefix :api
           mount API::Users
           mount API::Social => "/social"
         end
       end
       RUBY
      "app/api/users.rb" => <<-RUBY,
        module API
          class Users < Grape::API
            resource :users do
              params do
                optional :page, type: Integer
              end
              get do
              end
              params do
                requires :name, type: String
              end
              post do
              end
            end
          end
        end
        RUBY
      "app/api/social.rb" => <<-RUBY,
        module API
          class Social < Grape::API
            get :feed do
            end
          end
        end
        RUBY
    })

    find_ep(endpoints, "GET", "/social/api/feed")
    param_names(find_ep(endpoints, "GET", "/api/users"), "query").should eq(%w[page])
    param_names(find_ep(endpoints, "POST", "/api/users"), "json").should eq(%w[name])
  end

  it "prefixes modular Sinatra apps with their config.ru mapping" do
    endpoints = scan_ruby_tree({
      "Gemfile"   => %(source "https://rubygems.org"\ngem "sinatra"\n),
      "config.ru" => <<-RUBY,
        require_relative "app/api"
        map "/api/v1" do
          run Api::App
        end
        run Rack::URLMap.new("/admin" => Admin, "/" => Web)
        RUBY
      "app/api.rb"   => "require 'sinatra/base'\nmodule Api\n  class App < Sinatra::Base\n    get '/items' do\n    end\n  end\nend\n",
      "app/admin.rb" => "require 'sinatra/base'\nclass Admin < Sinatra::Base\n  get '/stats' do\n  end\nend\n",
      "app/web.rb"   => "require 'sinatra/base'\nclass Web < Sinatra::Base\n  get '/hello' do\n  end\nend\n",
    })

    find_ep(endpoints, "GET", "/api/v1/items")
    find_ep(endpoints, "GET", "/admin/stats")
    find_ep(endpoints, "GET", "/hello")
  end
end
