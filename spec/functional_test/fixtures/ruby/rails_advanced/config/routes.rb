Rails.application.routes.draw do
  root "home#index"

  # Regression guard: a local string variable + `#{var}` interpolation
  # should resolve to the literal value. Both routes below should end
  # up with `/c/:channel_title/:channel_id` substituted into the URL.
  base_c_route = "/c/:channel_title/:channel_id"
  get "#{base_c_route}/:message_id" => "chat#respond"
  post "#{base_c_route}/messages" => "chat#create"

  # Regression guard: a `#{...}` interpolation that embeds its own quotes
  # (an ENV lookup with a default) must not truncate the path at the inner
  # quote — the old matcher surfaced a malformed `/#{ENV.fetch('` route.
  get "/#{ENV.fetch('URL_COMPONENT', 'bb')}/:area" => "billboards#show"

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

    # #3267: a one-segment route names no controller, so Rails uses the
    # namespace module: `admin#dashboard` in AdminController.
    get "dashboard"
    post "rebuild"
    get "with-dash"
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
    collection { get :inline_summary }
    member { post :inline_preview }

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

  # A concern's member/collection routes hang off the resource naming it,
  # here through `with_options`, whose `only:` also holds for `resources`.
  namespace :trends do
    concern :reviewable do
      member do
        post :approve
      end
      collection { post :batch }
    end

    with_options only: [:index], concerns: :reviewable do
      resources :tags
    end

    # A predicate action: the `def` is `merged?`.
    get :merged, to: "tags#merged?"
  end

  # NotificationsController inherits `show`/`update` from its base class.
  namespace :preferences do
    resource :notifications, only: [:show, :update]
  end

  get "up" => "rails/health#show"
  get "ping", to: "monitor#ping"
  match "legacy_ping", to: "monitor#ping", via: "get"

  # Optional route segments are Rails DSL, not URL: `(.:format)` and the
  # nested `(/:section)` must be peeled to the required base path, and the
  # `//` left where a middle segment is removed must collapse.
  get "feed(.:format)", to: "monitor#ping"
  get "report(/:section)/rss", to: "monitor#ping"
  get "archive(/:year)(/:month)", to: "monitor#ping"

  # Optional segments in scope prefixes should be normalized the same way as
  # route literals; the emitted URL is `/localized_ping`, not `/(/:locale)/...`.
  scope "(/:locale)" do
    get "localized_ping", to: "monitor#ping"
  end

  # A `%w[...].each do |action|` loop over a literal list (like Redmine's
  # repository routes) unrolls to one route per element with `#{action}`
  # substituted — never leaking raw Ruby or a fabricated `{action}` path
  # param into the URL. The `.each do` block is also a transparent scope —
  # the route after it keeps the root prefix.
  %w[browse annotate].each do |action|
    get "repo/:id/#{action}", to: "monitor#ping"
  end

  devise_for :users
  devise_for :admins, only: [:sessions]
  devise_for :members, only: [:sessions, :registrations], skip: [:registrations]
  devise_scope :user do get 'login', to: 'devise/sessions#new' end

  mount Sidekiq::Web, at: "/sidekiq"

  get(
    "/split",
    controller: "monitor",
    action: :ping
  )

  # Hash-rocket `scope :module =>` adds no path segment; `namespace
  # module:` names the controllers; a slashed `ctrl#action` inside a
  # namespace still gets its module; `namespace path: ""` adds none.
  namespace :api, :path => "api/0.6" do
    resources :changesets, :path => "changeset", :only => [:show] do
      scope :module => :changesets do
        resource :download, :only => :show
      end
    end
    post "changeset/:changeset_id/hide" => "changesets/visibilities#destroy"
  end
  namespace :profile, :module => :profiles do
    resource :description, :only => [:show]
    resource :summary, :path => "(:kind)", :only => :show
  end
  namespace :feeds, :path => "" do
    resource :legacy, :path => "/feeds/legacy", :only => :show
  end

  draw :external

  scope :v1 do
    draw :external
  end

  scope :v2 do
    draw :external
  end
end
