from masonite.routes import Route

ROUTES = [
    Route.get("/users/@uid", "UserController@show"),
]
