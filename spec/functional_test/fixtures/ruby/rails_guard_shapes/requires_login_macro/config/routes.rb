Rails.application.routes.draw do
  resources :drafts, only: [:index, :destroy]
  resources :posts, only: [:show]
end
