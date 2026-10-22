package com.example;

import io.javalin.Javalin;

public class JavalinApp {
    public static void main(String[] args) {
        Javalin app = Javalin.create();
        app.get("/javalin/users", ctx -> ctx.result("ok"));
        app.get("javalin/ping", JavalinApp::ping);

        // Not a route: a config lookup with a class literal.
        Settings settings = null;
        settings.get("db.url", String.class);
    }

    static void ping(io.javalin.http.Context ctx) {
    }

    interface Settings {
        Object get(String key, Class<?> type);
    }
}
