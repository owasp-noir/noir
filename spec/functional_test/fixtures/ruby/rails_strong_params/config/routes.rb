Rails.application.routes.draw do
  resources :articles, only: %i[update]
  resources :comments, only: %i[create]
  resources :books, only: %i[create update]
  resources :pages, only: %i[update]
  resources :organizations, only: %i[show] do
    resources :users, only: %i[index], to: "organizations#users"
  end
end
