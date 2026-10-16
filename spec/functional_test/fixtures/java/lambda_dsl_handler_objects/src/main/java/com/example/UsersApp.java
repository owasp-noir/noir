package com.example;

import io.javalin.Javalin;
import io.javalin.http.Handler;
import io.javalin.http.HandlerType;
import java.util.HashMap;
import java.util.Map;
import static io.javalin.apibuilder.ApiBuilder.*;

public class UsersApp {
    public static void main(String[] args) {
        Handler getOne = ctx -> ctx.result(ctx.pathParam("id"));
        Handler listAll = ctx -> ctx.result("all");
        Map<String, Object> sessions = new HashMap<>();

        Javalin app = Javalin.create();
        app.routes(() -> {
            path("users", () -> {
                get(listAll);
                get("{id}", getOne);
                post("new", new CreateUserHandler());
            });
            get("reports", listAll);
            before(ctx -> sessions.put("started", new CreateUserHandler()));
        });

        app.addHandler(HandlerType.GET, "users/{id}/profile", getOne);
        app.addHandler(HandlerType.GET, "health", getOne);
        app.get("items/{id}", getOne);
        app.get("files/list", getOne);

        // Not routes: collection and JDBC lookups that share the verb names.
        sessions.put("k", new CreateUserHandler());
        sessions.put("handlers", getOne);
        Row row = null;
        row.get("C", String.class);
    }

    static class CreateUserHandler implements Handler {
        public void handle(io.javalin.http.Context ctx) {
            String name = ctx.formParam("name");
        }
    }

    interface Row {
        Object get(String key, Class<?> type);
    }
}
