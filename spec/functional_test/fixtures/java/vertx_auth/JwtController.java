package com.example;

import io.vertx.ext.web.Router;

public class JwtController {
    public void setup(Router router) {
        // Route with JWTAuth handler
        router.route("/api/secure").handler(JWTAuth.create(vertx, config));
        router.get("/api/secure").handler(ctx -> {
            ctx.response().end("secure");
        });
    }
}
