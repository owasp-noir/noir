Rails.application.routes.draw do
  get   "/timeline", to: "posts#index"
  post  "/posts",     to: "posts#create"
  patch "/posts/:id", to: "posts#update"
  post  "/comments",  to: "posts#comment"
end
