Rails.application.routes.draw do
  get '/home', to: 'home#index'
  # Listed, never loaded.
  Dir.glob("#{__dir__}/routes/*.rb").each { |f| puts f }
  # Loaded, but not config/routes.
  Dir[Rails.root.join('app/routes/*.rb')].each { |f| load f }
  Dir.glob("lib/routes/*.rb").each do |file|
    require file
  end
end
