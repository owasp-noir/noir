Rails.application.routes.draw do
  resources :posts, only: [:update, :destroy]
  resources :reports, only: [:index]
end
