Rails.application.routes.draw do
  resources :posts, only: [:index, :show, :create, :destroy]
  resources :articles, only: [:index, :show] do
    get :feed, on: :collection
  end
end
