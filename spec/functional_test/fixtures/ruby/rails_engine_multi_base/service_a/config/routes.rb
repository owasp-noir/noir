Rails.application.routes.draw do
  mount Blog::Engine, at: "/a-engine"
end

Blog::Engine.routes.draw do
  get "/posts" => "posts#index"
end
