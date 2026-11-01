Rails.application.routes.draw do
  get '/init', to: 'init#index'
  root 'init#index'

  # Every file under config/routes/ draws its own routes.
  dir = File.expand_path(__dir__)
  files = Dir.glob("#{dir}/routes/*.rb")
  files.each do |file|
    load file
  end

  match '*a', to: 'errors#routing', via: :get
end
