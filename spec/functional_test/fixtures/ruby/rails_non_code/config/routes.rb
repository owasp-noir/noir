Rails.application.routes.draw do
  get '/real', to: 'pages#show'
=begin
  get '/dead', to: 'pages#show'
=end
  ROUTE_DOC = <<~TXT
    get '/in-heredoc', to: 'pages#show'
  TXT
  post '/after', to: 'pages#create'
end
