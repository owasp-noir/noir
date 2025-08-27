Marten.routes.draw do
  path "/", HomeHandler, name: "home"
  path "/api/users", UsersHandler, name: "users"
  path "/api/users/<id:int>", UserDetailHandler, name: "user_detail"
  path "/auth/login", LoginHandler, name: "login"
  path "/products", ProductsHandler, name: "products"
  path "/products/<slug:str>", ProductDetailHandler, name: "product_detail"
end