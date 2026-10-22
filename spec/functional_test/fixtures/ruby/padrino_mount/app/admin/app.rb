class Admin < Padrino::Application
  get '/dashboard' do
    params[:range]
  end
end
