from masonite.routes import Route

ROUTES = [
    Route.get("/b-items", "ItemController@index"),
]
