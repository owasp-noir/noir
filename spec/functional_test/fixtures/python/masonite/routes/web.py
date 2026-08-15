"""Web Routes."""
from masonite.routes import Route

from app.controllers.UserController import UserController

ROUTES = [
    # String controller binding ("preferred" per docs), '__call__' default.
    Route.get("/", "WelcomeController@show"),

    # Class/method controller binding.
    Route.post("/users", UserController.store),

    # Required + typed + optional path parameters.
    Route.get("/users/@id", UserController.show),
    Route.get("/typed/@id:integer", UserController.show),
    Route.get("/search/?term", UserController.search),

    # Nested groups: prefix composes outer -> inner.
    Route.group([
        Route.get("/settings", UserController.settings),
        Route.group([
            Route.put("/profile", UserController.update_profile),
        ], prefix="/security"),
    ], prefix="/account", middleware=["auth"]),

    # Group whose inner route is bare "/" — must not leave a trailing slash.
    Route.group([
        Route.get("/", UserController.index),
        Route.post("/", UserController.create),
    ], prefix="/admin/users"),

    # Resource + API resource expansion.
    *Route.resource("posts", "PostController"),
    *Route.api("api/posts", "PostController"),

    # Specialized helpers.
    Route.view("/about", "about"),
    Route.redirect("/old-home", "/"),
    Route.permanent_redirect("/legacy", "/"),

    # any() / match() helpers.
    Route.any("/webhook", UserController.webhook),
    Route.match(["put", "patch"], "/users/@id/touch", UserController.touch),

    # Unresolvable controller reference — must still surface a bare endpoint.
    Route.get("/health", "MissingController@ping"),
]
