Sample::Application.routes.draw do
  api_path = Rails.configuration.api_path

  # match '/ignored_in_comment', to: 'tickets#index', via: :get
  match api_path + '/tickets',     to: 'tickets#index',  via: :get
  match api_path + '/tickets/:id', to: 'tickets#update', via: :put

  scope api_path do
    resources :tickets, only: [] do
      collection do
        post 'merge/:id', action: :merge
        match :search, via: %i[get post]
      end
    end
  end

  scope Rails.configuration.api_path do
    get '/ticket_stats', to: 'tickets#stats'
  end
end
