Sample::Application.routes.draw do
  # production.rb overrides application.rb.
  get Rails.configuration.base + '/a', to: 'tickets#index'
  # Only development.rb differs; production keeps application.rb.
  get Rails.configuration.devonly + '/b', to: 'tickets#index'
  # Set conditionally in production.rb: unknown, so no route.
  get Rails.configuration.cond + '/c', to: 'tickets#index'

  api_path = Rails.configuration.api_path
  scope path: api_path do
    get '/scoped', to: 'tickets#index'
  end
  # Rebound to something unknown: the old value must not leak.
  api_path = ENV['OTHER_PATH']
  get api_path + '/stale', to: 'tickets#index'
  get "#{api_path}/stale_interp", to: 'tickets#index'
end
