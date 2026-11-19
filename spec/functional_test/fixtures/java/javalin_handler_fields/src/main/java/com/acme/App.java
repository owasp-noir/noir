package com.acme;

import io.javalin.Javalin;

public class App {
    public static void main(String[] args) {
        Javalin app = Javalin.create().start(7000);
        UserController users = new UserController();

        // Static `Handler` fields declared in another class.
        app.get("/users", UserController.fetchAllUsernames);
        app.get("/users/{id}", UserController.fetchById);
        // Handler returned by a factory method.
        app.post("/users", users.create());
        // Control: lambda and method reference.
        app.get("/control-lambda", ctx -> ctx.result("x"));
        app.delete("/control-ref/{id}", App::remove);
        // Map calls with a value expression are not routes.
        java.util.Map<String, String> settings = new java.util.HashMap<>();
        settings.put("key", users.toString());
    }

    static void remove(io.javalin.http.Context ctx) {}
}
