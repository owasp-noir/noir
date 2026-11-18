Rails.application.routes.draw do
  devise_for :accounts, controllers: { sessions: "accounts/sessions", passwords: "accounts/passwords" }
  resources :articles, only: %i[update]
  resources :comments, only: %i[create]
  resources :books, only: %i[create update]
  resources :pages, only: %i[update]
  resources :items, only: %i[create update]
  resources :orders, only: %i[create]
  resources :notes, only: %i[create]
  resources :organizations, only: %i[show] do
    resources :users, only: %i[index], to: "organizations#users"
  end
end
