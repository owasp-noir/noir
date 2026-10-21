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
    param_names(find_ep(endpoints, "PATCH", "/products/:id"), "form").should eq(%w[sku])
  end

  it "merges a Rails action's helper params in the order the helpers are defined" do
    endpoints = scan_ruby_tree({
      "Gemfile"                               => RAILS_GEMFILE,
      "config/routes.rb"                      => "Rails.application.routes.draw do\n  get '/reports', to: 'reports#index'\nend\n",
      "app/controllers/reports_controller.rb" => <<-RUBY,
        class ReportsController < ApplicationController
          def alpha_filter
            params[:alpha]
          end

          def beta_filter
            params[:beta]
          end

          def index
            beta_filter
            alpha_filter
            params[:page]
          end
        end
        RUBY
    })

    report = find_ep(endpoints, "GET", "/reports")
    report.params.select(&.param_type.==("query")).map(&.name).should eq(%w[page alpha beta])
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

    urls.should contain("GET /posts/:post_id/comments")
    urls.should contain("POST /posts/:post_id/comments")
    urls.should contain("GET /comments/:id")
    urls.should contain("DELETE /comments/:id")
    urls.should contain("POST /comments/:id/approve")
    urls.should contain("GET /admin/posts/:post_id/comments")
    urls.should contain("GET /admin/comments/:id")
    urls.should_not contain("GET /posts/:post_id/comments/:id")
    urls.should_not contain("GET /admin/posts/:post_id/comments/:id")
  end

  it "names Rails resource keys the way Rails routes them" do
    controller = "class StatusesController < ApplicationController\n  def show; end\nend\n"
    endpoints = scan_ruby_tree({
      "Gemfile"          => RAILS_GEMFILE,
      "config/routes.rb" => <<-RUBY,
        Rails.application.routes.draw do
          resources :statuses, only: [:show] do
            resource :context, only: [:show]
            get :history
            member do
              post :pin
            end
            collection do
              get :recent
            end
          end
          resources :articles, param: :slug, only: [] do
            resources :comments, only: [:show]
          end
          resources :photos, as: :images, only: [] do
            get :preview
          end
        end
        RUBY
      "app/controllers/statuses_controller.rb" => controller,
      "app/controllers/contexts_controller.rb" => "class ContextsController < ApplicationController\n  def show; end\nend\n",
      "app/controllers/comments_controller.rb" => "class CommentsController < ApplicationController\n  def show; end\nend\n",
    })
    urls = endpoints.map { |e| "#{e.method} #{e.url}" }

    urls.should contain("GET /statuses/:id")
    urls.should contain("GET /statuses/:status_id/context")
    urls.should contain("GET /statuses/:status_id/history")
    urls.should contain("POST /statuses/:id/pin")
    urls.should contain("GET /statuses/recent")
    urls.should contain("GET /articles/:article_slug/comments/:id")
    urls.should contain("GET /photos/:image_id/preview")
    param_names(find_ep(endpoints, "GET", "/articles/:article_slug/comments/:id"), "path").should eq(%w[article_slug id])
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

  it "reads only HTTP_* Rack env keys as headers, by their header name" do
    route = <<-RUBY
      get '/whoami' do
        auth = request.env["omniauth.auth"]
        ip = request.env["REMOTE_ADDR"]
        ua = request.env["HTTP_USER_AGENT"]
      end
      RUBY
    sinatra = scan_ruby_tree({
      "Gemfile" => %(source "https://rubygems.org"\ngem "sinatra"\n),
      "app.rb"  => "require 'sinatra'\n#{route}",
    })
    padrino = scan_ruby_tree({
      "Gemfile"    => %(source "https://rubygems.org"\ngem "padrino"\n),
      "app/app.rb" => "class Demo < Padrino::Application\n#{route}end\n",
    })

    {sinatra, padrino}.each do |endpoints|
      param_names(find_ep(endpoints, "GET", "/whoami"), "header").should eq(%w[User-Agent])
    end
  end

  it "types Hanami params once and keeps slice routes to their own actions" do
    endpoints = scan_ruby_tree({
      "Gemfile"          => %(gem "hanami", "~> 2.1"\n),
      "config/routes.rb" => <<-RUBY,
        module Bookshelf
          class Routes < Hanami::Routes
            get "/books", to: "books.index"
            post "/books", to: "books.create"
            slice :admin, at: "/admin" do
              get "/books", to: "books.index"
            end
          end
        end
        RUBY
      "app/actions/books/index.rb" => <<-RUBY,
        class Index < Bookshelf::Action
          params do
            optional(:page).value(:integer)
          end
          def handle(request, response)
            request.params[:page]
          end
        end
        RUBY
      "app/actions/books/create.rb" => <<-RUBY,
        class Create < Bookshelf::Action
          params do
            required(:title).filled(:string)
          end
          def handle(request, response)
            request.params[:title]
          end
        end
        RUBY
      "slices/admin/actions/books/index.rb" => "class Index < Admin::Action\n  def handle(request, response)\n    request.params[:q]\n  end\nend\n",
    })

    find_ep(endpoints, "GET", "/books").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[page:query])
    find_ep(endpoints, "POST", "/books").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[title:json])
    find_ep(endpoints, "GET", "/admin/books").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[q:query])
  end

  it "models Devise skip:/only:, :omniauthable, devise_scope, and config.sign_out_via" do
    endpoints = scan_ruby_tree({
      "Gemfile"                       => RAILS_GEMFILE,
      "config/initializers/devise.rb" => "Devise.setup do |config|\n  config.sign_out_via = [:get, :delete]\nend\n",
      "app/models/user.rb"            => "class User < ApplicationRecord\n  devise :database_authenticatable, :registerable, :omniauthable\nend\n",
      "config/routes.rb"              => "Rails.application.routes.draw do\n  devise_for :users, skip: [:registrations]\n  devise_scope :user do get 'login', to: 'devise/sessions#new' end\nend\n",
    })
    urls = endpoints.map { |e| "#{e.method} #{e.url}" }

    urls.should contain("GET /users/sign_in")
    urls.should contain("POST /users/sign_in")
    urls.should contain("GET /users/sign_out")
    urls.should contain("DELETE /users/sign_out")
    urls.should contain("GET /users/auth/:provider")
    urls.should contain("POST /users/auth/:provider")
    urls.should contain("GET /users/auth/:provider/callback")
    urls.should contain("POST /users/auth/:provider/callback")
    urls.should contain("GET /login")
    urls.should_not contain("GET /users/sign_up")
    urls.should_not contain("POST /users")
    find_ep(endpoints, "POST", "/users/sign_in").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:form password:form])
  end

  it "uses a subclass's redefined Devise param reader instead of Devise's built-in defaults" do
    endpoints = scan_ruby_tree({
      "Gemfile"                                   => RAILS_GEMFILE,
      "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::API\nend\n",
      "app/controllers/sessions_controller.rb"    => <<-RUBY,
        class SessionsController < Devise::SessionsController
          private
          def sign_in_params
            params.require(:user).permit(:username, :otp)
          end
        end
        RUBY
      "config/routes.rb" => "Rails.application.routes.draw do\n  devise_for :users, controllers: { sessions: :sessions }\nend\n",
    })

    find_ep(endpoints, "POST", "/users/sign_in").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[username:json otp:json])
    find_ep(endpoints, "POST", "/users").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:json password:json password_confirmation:json])
    find_ep(endpoints, "PATCH", "/users").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:json password:json password_confirmation:json current_password:json])
    find_ep(endpoints, "POST", "/users/password").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:json])
    find_ep(endpoints, "PUT", "/users/password").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[reset_password_token:json password:json password_confirmation:json])
    find_ep(endpoints, "POST", "/users/confirmation").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:json])
    find_ep(endpoints, "POST", "/users/unlock").params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(%w[email:json])
  end
end
