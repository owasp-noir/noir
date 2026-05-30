namespace "users" do
  post "/", to: "users#create"
  post "/login", to: "users#login"
end

namespace "articles" do
  get "/:slug", to: "articles#show"
end
