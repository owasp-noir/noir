package com.example;

import static spark.Spark.*;

public class Application {
    private static final String API_PREFIX = "/api";
    private static final String REPORTS_PATH = "/reports";
    private static final String SOCKET_PATH = "/events";
    private static final String TRACE_HEADER = "X-Report-Trace";

    static final class RouteParts {
        static final String DETAIL = "/:reportId";
    }

    public static void main(String[] args) {
        staticFiles.location("/public");
        staticFiles.externalLocation("/var/www/public");

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

        redirect.get("/legacy-home", "/hello");
        redirect.post("/legacy-submit", "/api/v1/submit", Redirect.Status.SEE_OTHER);
        redirect.any("/legacy-any", "/hello", Redirect.Status.MOVED_PERMANENTLY);

        path(API_PREFIX, () -> {
            get(REPORTS_PATH + RouteParts.DETAIL, (req, res) -> {
                String trace = req.headers(TRACE_HEADER);
                return trace;
            });
            webSocket(SOCKET_PATH + "/:roomId", EventsSocket.class);
        });
    }

    static class EventsSocket {
    }
}
