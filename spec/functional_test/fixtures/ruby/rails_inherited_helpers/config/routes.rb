Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :blocks, only: [:index]
      resources :mutes, only: [:index]
      get "search", to: "search#index"
    end
  end
end
