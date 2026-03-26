package com.example;

import io.vertx.ext.web.Router;

public class DashboardController {
    public void setup(Router router) {
        // Route with BasicAuthHandler
        router.get("/admin/dashboard").handler(BasicAuthHandler.create(authProvider));
        router.get("/admin/dashboard").handler(ctx -> {
            ctx.response().end("dashboard");
        });
    }
}
