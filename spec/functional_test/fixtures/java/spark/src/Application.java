package com.example;

import static spark.Spark.*;

public class Application {
    public static void main(String[] args) {
        get("/hello", (req, res) -> {
            String name = req.queryParams("name");
            return "Hello " + name;
        });

        post("/users", (req, res) -> {
            String body = req.body();
            res.status(201);
            return body;
        });

        path("/api", () -> {
            get("/status", (req, res) -> "ok");
            path("/v1", () -> {
                get("/health", (req, res) -> "healthy");
                post("/submit", (req, res) -> {
                    String body = req.body();
                    String token = req.headers("X-Token");
                    return body;
                });
                get("/items/:itemId", (req, res) -> {
                    String category = req.queryParams("category");
                    return "ok";
                });
            });
        });

        delete("/sessions/:id", (req, res) -> {
            String session = req.cookie("session");
            res.status(204);
            return "";
        });

        Spark.put("/profile", (req, res) -> {
            String body = req.body();
            String trace = req.headers("X-Trace");
            return body;
        });
    }
}
