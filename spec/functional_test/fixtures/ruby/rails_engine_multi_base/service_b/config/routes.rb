Rails.application.routes.draw do
  mount Blog::Engine, at: "/b-engine"
end

Blog::Engine.routes.draw do
  get "/posts" => "posts#index"
end
