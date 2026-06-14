module Auth
  ROUTES = Marten::Routing::Map.draw do
    path "/signin", SignInHandler, name: "sign_in"
    path "/signup", SignUpHandler, name: "sign_up"
  end
end
