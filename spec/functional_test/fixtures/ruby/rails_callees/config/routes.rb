Rails.application.routes.draw do
  resources :posts, only: [:index, :show, :create] do
    member do
      delete :memory, action: :destroy_memory
      get :external_ready, to: "monitor#ready"
    end

    collection do
      get :preview
    end
  end

  get "status", to: "monitor#status"
  get "ping", to: "monitor#ping"
  get "ready", to: "monitor#ready"

  post "posts/implicit_preview", format: "json"
  post "posts/implicit_preview_legacy", :format => "json"
end
