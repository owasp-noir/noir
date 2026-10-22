class CoreApp < Padrino::Application
  get '/' do
    'core home'
  end

  get '/health' do
    'ok'
  end
end
