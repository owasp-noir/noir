Rails.application.routes.draw do
  resources :posts, only: [:index, :show, :create] do
    collection do
      get :preview
    end
  end

  get "status", to: "monitor#status"
  get "ping", to: "monitor#ping"
  get "ready", to: "monitor#ready"
end
