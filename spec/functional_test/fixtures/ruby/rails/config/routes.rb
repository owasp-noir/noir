Rails.application.routes.draw do
  resources :posts do
    member do
      query :search
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
