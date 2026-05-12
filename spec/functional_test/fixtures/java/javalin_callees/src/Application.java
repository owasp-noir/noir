package com.example;

import io.javalin.Javalin;

public class Application {
    public static void main(String[] args) {
        Javalin app = Javalin.create();

        app.post("/users", ctx -> {
            String name = ctx.queryParam("name");
            String saved = UserService.save(name);
            AuditLog.write(saved);
            ctx.result(saved);
        });

        app.get("/profile", ctx -> {
            String built = buildProfile();
            AuditLog.write(built);
            ctx.result(built);
        });

        app.get("/legacy", ctx -> {
            AuditLog.write("legacy");
            ctx.result(getLegacy().toString());
        });

        app.start();
    }

    static String buildProfile() {
        return "profile";
    }

    static String getLegacy() {
        return "legacy";
    }
}
