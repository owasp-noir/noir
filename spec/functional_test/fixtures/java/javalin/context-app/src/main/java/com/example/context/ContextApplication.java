package com.example.context;

import io.javalin.Javalin;

public class ContextApplication {
    private static final String CONTEXT_ROOT = "/portal";

    public static void main(String[] args) {
        Javalin app = Javalin.create(config -> {
            config.router.contextPath = CONTEXT_ROOT;
        });

        app.get("/context/status", ctx -> ctx.result("ok"));
    }
}
