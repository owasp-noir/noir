Rails.application.routes.draw do
  root "home#index"

  namespace :admin do
    resources :reports
    resources :refunds do
      member do
        post :change_status
        delete :purge
        post :update_metadata
      end
      collection do
        get :new_list
      end
    end

    get "monitor/heartbeat", to: "monitor#heartbeat"
  end

  scope :api do
    resources :items, only: [:index, :show]
  end

  scope path: "internal" do
    resources :statements, except: [:destroy]
  end

  resources :scans, controller: "billing/scans", only: [:index]

  resources :posts do
    resources :comments
  end

  get "up" => "rails/health#show"
  get "ping", to: "monitor#ping"

  devise_for :users

  mount Sidekiq::Web, at: "/sidekiq"
end
