Rails.application.routes.draw do
  resources :drafts, only: [:destroy]
  resources :posts, only: [:show]
end
