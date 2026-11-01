Rails.application.routes.draw do
  get "/up", to: "pages#up"

  if Rails.env.test?
    get "/test_only", to: "pages#test_only"
    namespace :fixtures do
      resources :seeds, only: :index
    end
  end

  if Rails.env.development? || Rails.env.test?
    get "/dev_only", to: "pages#dev_only"
  else
    get "/prod_branch", to: "pages#prod_branch"
  end

  unless Rails.env.production?
    get "/not_prod", to: "pages#not_prod"
  end

  get "/become", to: "pages#become" if !Rails.env.production?

  # Production can satisfy these, so their routes stay.
  if Rails.env.production?
    get "/prod_only", to: "pages#prod_only"
  end
  if Rails.env.test? || ENV["DEMO"]
    get "/demo", to: "pages#demo"
  end
  if Rails.env.development? && ENV["X"] || ENV["Y"]
    get "/either", to: "pages#either"
  end

  get "/after", to: "pages#after"
end
