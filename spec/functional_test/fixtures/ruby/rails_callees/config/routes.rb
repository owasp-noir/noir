Rails.application.routes.draw do
  resources :posts, only: [:index, :show, :create] do
    collection do
      get :preview
    end
  end

  get "status", to: "monitor#status"
end
