package com.example;

import io.vertx.ext.web.Router;

public class ProfileController {
    public void setup(Router router) {
        // Route checking user in handler
        router.get("/api/profile").handler(ctx -> {
            var user = routingContext.user();
            ctx.response().end(user.toString());
        });
    }
}
