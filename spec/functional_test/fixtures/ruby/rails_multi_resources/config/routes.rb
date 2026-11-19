Rails.application.routes.draw do
  resources :photos, :books, :videos, only: [:index, :show]
  resource :profile, :settings, only: [:show]
  # A hash-rocket option is not a second resource.
  resources :users, :only => [:index]
end
