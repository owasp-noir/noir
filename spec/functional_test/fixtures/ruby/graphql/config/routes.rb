Rails.application.routes.draw do
  post "/api/graphql", to: "graphql#execute"
end
