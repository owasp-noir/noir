module Blog
  ROUTES = Marten::Routing::Map.draw do
    path "/", HomeHandler, name: "home"
    path "/posts/<slug:slug>", PostDetailHandler, name: "post_detail"
  end
end
