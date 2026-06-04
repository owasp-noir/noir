module Testapp
  class Routes < Hanami::Routes
    root to: "home.show"
    get "/#{API_PREFIX}/items", to: "health.ready"
    get "/secure", to: "secure.show"

    scope "/api" do
      get "/health", to: "health.ready"
    end

    scope "/block" do
      get "/inline" do
        "ok"
      end

      get "/after", to: "health.ready"
    end

    slice :main, at: "/" do
      resources :cafes, only: %i[show] do
        resources :reviews, only: %i[new create]
      end

      resource :account, only: %i[show]

      post "/widgets/:id/build",
           to: "widgets.build"
    end

    mount Sidekiq::Web, at: "/sidekiq"
  end
end
