package com.example;

import io.vertx.ext.web.Router;

public class HealthController {
    public void setup(Router router) {
        // No auth patterns at all
        router.get("/public/health").handler(ctx -> {
            ctx.response().end("ok");
        });
    }
}
