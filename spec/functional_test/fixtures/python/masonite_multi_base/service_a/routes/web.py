from masonite.routes import Route

ROUTES = [
    Route.get("/a-items", "ItemController@index"),
]
