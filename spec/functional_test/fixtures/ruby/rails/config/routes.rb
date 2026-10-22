Rails.application.routes.draw do
  resources :posts do
    member do
      query :search
    end
  end

  resources :articles, only: [:create, :update]

  scope :api do
    # `controllers:` swaps the sessions controller for the app's own and
    # `path_names:` renames sign_in; the model picks the Devise modules.
    devise_for :users, controllers: { sessions: :sessions },
                       path_names: { sign_in: :login }

    # `param:` renames the member key; nested routes see `profile_username`.
    resources :profiles, param: :username, only: [:show] do
      resource :follow, only: [:create, :destroy]
    end
  end

  query "search", to: "posts#index"
  match "filter", to: "posts#index", via: :query
  match "both", to: "posts#index", via: [:get, :query]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Defines the root path route ("/")
  # root "articles#index"
  get "up" => "rails/health#show", as: :rails_health_check
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
