Rails.application.routes.draw do
  root "home#index"

  namespace :admin do
    resources :reports
    resources :quests do
      member do
        post :change_status
      end
      collection do
        get :new_list
      end
    end
  end

  scope :api do
    resources :items, only: [:index, :show]
  end

  scope path: "intel" do
    resources :feeds, except: [:destroy]
  end

  resources :scans, controller: "ye_ot/scans", only: [:index]

  resources :posts do
    resources :comments
  end

  get "up" => "rails/health#show"
  get "ping", to: "monitor#ping"

  devise_for :users

  mount Sidekiq::Web, at: "/sidekiq"
end
