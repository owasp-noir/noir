Rails.application.routes.draw do
  root "home#index"

  # Regression guard: a local string variable + `#{var}` interpolation
  # should resolve to the literal value. Both routes below should end
  # up with `/c/:channel_title/:channel_id` substituted into the URL.
  base_c_route = "/c/:channel_title/:channel_id"
  get "#{base_c_route}/:message_id" => "chat#respond"
  post "#{base_c_route}/messages" => "chat#create"

  namespace :admin do
    resources :reports
    resources :refunds do
      member do
        post :change_status
        delete :purge
        post :update_metadata
      end
      collection do
        get :new_list
      end
    end

    get "monitor/heartbeat", to: "monitor#heartbeat"

    # Regression guard: an `if Rails.env.test? ... end` conditional (a
    # common dev/test-only routing idiom) must not pop the surrounding
    # `namespace :admin`. Without crediting the keyword block, the `end`
    # below stripped `/admin` from every route that followed —
    # `after_conditional` leaked out as `/after_conditional`.
    if Rails.env.test?
      get "debug/echo", to: "monitor#heartbeat"
    end

    get "after_conditional", to: "monitor#heartbeat"
  end

  namespace :admin, path: "sekret" do
    resources(:reports, only: %i[index show])
  end

  scope "/backoffice", module: "admin" do
    get "heartbeat", to: "monitor#heartbeat"
  end

  scope module: :admin do
    get "module_ping", controller: "monitor", action: :heartbeat
  end

  controller :monitor do
    get "controller_ping" => :ping
  end

  scope :api do
    resources :items, only: [:index, :show]
  end

  scope path: "internal" do
    resources :statements, except: [:destroy]
  end

  resources :scans, controller: "billing/scans", only: [:index]

  resources :legacy_posts,
            controller: "posts",
            only: [
              :index,
              :show,
            ]

  resources :refunds, controller: "admin/refunds", only: [] do
    get :summary, on: :collection
    get :preview

    new do
      get :template
    end
  end

  concern :commentable do
    resources :comments, only: [:index, :show] do
      resources :likes, only: [:index, :show]
    end
  end

  resources :posts, concerns: :commentable

  get "up" => "rails/health#show"
  get "ping", to: "monitor#ping"

  # Optional route segments are Rails DSL, not URL: `(.:format)` and the
  # nested `(/:section)` must be peeled to the required base path, and the
  # `//` left where a middle segment is removed must collapse.
  get "feed(.:format)", to: "monitor#ping"
  get "report(/:section)/rss", to: "monitor#ping"

  # Unresolved `#{...}` interpolation (a `.each` loop variable, like
  # Redmine's repository routes) must normalize to a `{placeholder}` and
  # never leak raw Ruby into the URL. The `.each do` block is also a
  # transparent scope — the route after it keeps the root prefix.
  %w[browse annotate].each do |action|
    get "repo/:id/#{action}", to: "monitor#ping"
  end

  devise_for :users

  mount Sidekiq::Web, at: "/sidekiq"

  get(
    "/split",
    controller: "monitor",
    action: :ping
  )

  draw :external

  scope :v1 do
    draw :external
  end

  scope :v2 do
    draw :external
  end
end
