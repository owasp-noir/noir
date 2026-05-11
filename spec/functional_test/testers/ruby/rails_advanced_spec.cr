require "../../func_spec.cr"

# Regression test for #1358: Rails routes.rb DSL features (namespace, scope,
# nested resources, member/collection, only:/except:, controller: override,
# root, devise_for, mount, hash-rocket form) must be parsed correctly.
expected_endpoints = [
  # root "home#index"
  Endpoint.new("/", "GET"),

  # namespace :admin do resources :reports end
  Endpoint.new("/admin/reports", "GET"),
  Endpoint.new("/admin/reports/1", "GET"),
  Endpoint.new("/admin/reports", "POST"),
  Endpoint.new("/admin/reports/1", "PUT"),
  Endpoint.new("/admin/reports/1", "DELETE"),

  # member/collection actions on namespaced resource
  Endpoint.new("/admin/refunds/1/change_status", "POST"),
  Endpoint.new("/admin/refunds/new_list", "GET"),

  # scope :api do resources :items, only: [:index, :show] end
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/1", "GET"),

  # scope path: "internal" do resources :statements, except: [:destroy] end
  Endpoint.new("/internal/statements", "GET"),
  Endpoint.new("/internal/statements/1", "GET"),
  Endpoint.new("/internal/statements", "POST"),
  Endpoint.new("/internal/statements/1", "PUT"),

  # resources :scans, controller: "billing/scans", only: [:index]
  Endpoint.new("/scans", "GET"),

  # nested resources :posts do resources :comments end
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/1", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/posts/1", "PUT"),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/posts/1/comments", "GET"),
  Endpoint.new("/posts/1/comments/1", "GET"),

  # hash-rocket and to: forms
  Endpoint.new("/up", "GET"),
  Endpoint.new("/ping", "GET"),

  # devise_for :users — sample of generated routes
  Endpoint.new("/users/sign_in", "GET"),
  Endpoint.new("/users/sign_in", "POST"),
  Endpoint.new("/users/sign_out", "DELETE"),
  Endpoint.new("/users/sign_up", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/password/new", "GET"),

  # mount Sidekiq::Web, at: "/sidekiq"
  Endpoint.new("/sidekiq", "GET"),
]

# Locking the total count ensures only:/except: filters drop the expected
# endpoints (e.g. no POST /api/items, no DELETE /internal/statements, no
# /scans/1) and devise_for emits its full route set.
total_endpoints = 1 +  # root
                  5 +  # admin/reports
                  2 +  # admin/refunds member+collection
                  2 +  # api/items only:[index,show]
                  4 +  # internal/statements except:[destroy]
                  1 +  # /scans only:[index] via controller override
                  5 +  # posts
                  2 +  # posts/1/comments
                  2 +  # /up + /ping
                  20 + # devise_for :users
                  1    # mount sidekiq

FunctionalTester.new("fixtures/ruby/rails_advanced/", {
  :techs     => 1,
  :endpoints => total_endpoints,
}, expected_endpoints).perform_tests
