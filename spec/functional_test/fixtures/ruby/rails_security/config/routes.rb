Rails.application.routes.draw do
  resources :users, only: [:index, :create, :update]
  resources :posts, only: [:index, :create]

  resources :webhooks, only: [:index, :create]
end
