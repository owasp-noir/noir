Rails.application.routes.draw do
  get "/up", to: "health#show"
  mount API::Base, at: "/api"
  mount Internal::API => "/internal"
end
