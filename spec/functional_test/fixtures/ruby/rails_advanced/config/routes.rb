Rails.application.routes.draw do
  root "home#index"

  # Regression guard: a local string variable + `#{var}` interpolation
  # should resolve to the literal value. Both routes below should end
  # up with `/c/:channel_title/:channel_id` substituted into the URL.
  base_c_route = "/c/:channel_title/:channel_id"
  get "#{base_c_route}/:message_id" => "chat#respond"
  post "#{base_c_route}/messages" => "chat#create"

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

  concern :commentable do
    resources :comments, only: [:index, :show] do
      resources :likes, only: [:index, :show]
    end
  end

  resources :posts, concerns: :commentable

  get "up" => "rails/health#show"
  get "ping", to: "monitor#ping"

  devise_for :users

  mount Sidekiq::Web, at: "/sidekiq"
end
