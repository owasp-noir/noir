module Testapp
  class Routes < Hanami::Routes
    root { "Hello from Hanami" }

    get "/books", to: "books.index"
    get "/books/:id", to: "books.show"
    get "/books/new", to: "books.new"
    post "/books", to: "books.create"
    patch "/books/:id", to: "books.update"
    delete "/books/:id", to: "books.destroy"

    get "/users/search", to: "users.search"
    post "/users", to: "users.create"
    get "/users/:id/profile", to: "users.profile"
  end
end