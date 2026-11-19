package com.acme;

import io.javalin.http.Handler;

public class UserController {
    public static Handler fetchAllUsernames = ctx -> {
        String filter = ctx.queryParam("filter");
        ctx.json(java.util.List.of());
    };

    public static Handler fetchById = ctx -> {
        String id = ctx.pathParam("id");
        ctx.json(id);
    };

    public Handler create() {
        return ctx -> ctx.status(201);
    }
}
