Rails.application.routes.draw do
  resources :books, only: [:index, :show, :edit, :destroy]
  resource :session, only: [:new, :create]
  get "/about", to: "books#about"
end
