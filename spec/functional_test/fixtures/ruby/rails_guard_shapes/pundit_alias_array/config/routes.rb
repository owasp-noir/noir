Rails.application.routes.draw do
  namespace :admin do
    resources :subscriptions, only: [:index] do
      collection do
        post :purge
        post :review
      end
    end
  end
end
