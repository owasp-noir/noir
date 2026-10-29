Shop::Engine.routes.draw do
  namespace :api do
    namespace :v3 do
      post 'auth/login', to: 'auth#create'
      resources :products, only: [:index, :show]
    end
  end
end
