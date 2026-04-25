package com.example;

import io.javalin.Javalin;

public class Application {
    public static void main(String[] args) {
        Javalin app = Javalin.create();

        app.get("/hello", ctx -> {
            String name = ctx.queryParam("name");
            ctx.result("Hello " + name);
        });

        app.post("/users", ctx -> {
            User user = ctx.bodyAsClass(User.class);
            ctx.json(user);
        });

        app.put("/users/{id}", ctx -> {
            String id = ctx.pathParam("id");
            User user = ctx.bodyAsClass(User.class);
            String trace = ctx.header("X-Trace");
            ctx.json(user);
        });

        app.routes(() -> {
            path("/api", () -> {
                get("/status", ctx -> ctx.result("ok"));
                path("/v1", () -> {
                    get("/health", ctx -> ctx.result("healthy"));
                    post("/submit", ctx -> {
                        Submission s = ctx.bodyAsClass(Submission.class);
                        String token = ctx.header("X-Token");
                        ctx.json(s);
                    });
                    get("/items/{itemId}", ctx -> {
                        String itemId = ctx.pathParam("itemId");
                        String category = ctx.queryParam("category");
                        ctx.result(itemId);
                    });
                });
            });
        });

        app.delete("/sessions/{id}", ctx -> {
            String id = ctx.pathParam("id");
            String session = ctx.cookie("session");
            ctx.status(204);
        });

        app.patch("/profile", ctx -> {
            String email = ctx.formParam("email");
            String phone = ctx.formParam("phone");
            ctx.result("ok");
        });

        app.start(7000);
    }

    static class User {
        public String name;
        public String email;
    }

    static class Submission {
        public String content;
    }
}
