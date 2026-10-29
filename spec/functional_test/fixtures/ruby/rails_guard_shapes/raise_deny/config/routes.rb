Rails.application.routes.draw do
  resources :drafts, only: [:destroy]
  namespace :admin do
    resources :backups, only: [:destroy]
  end
end
