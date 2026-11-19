Rails.application.routes.draw do
  %w[terms privacy].each do |page|
    get "/legal/#{page}", to: "pages#show"
  end

  [:about, :contact].each do |page|
    get "/#{page}", to: "pages#show"
  end

  ["facebook", "github"].each do |provider|
    get "/auth/#{provider}/callback", to: "sessions#create"
  end

  # An element only runtime knows: the loop stays as written.
  [Settings.home_page, :news].each do |page|
    get "/p/#{page}", to: "pages#show"
  end

  get "/after", to: "pages#show"
end
