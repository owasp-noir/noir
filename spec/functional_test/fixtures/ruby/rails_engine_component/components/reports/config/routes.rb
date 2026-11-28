Reports::Component.routes.draw do
  namespace :reports, path: nil do
    resources :summaries, only: [:index]
  end
end
