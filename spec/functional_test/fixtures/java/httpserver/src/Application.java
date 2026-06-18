package com.example;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;

public class Application {

    static final String API_BASE = "/api";

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(8000), 0);

        // 1. Lambda with no method guard -> defaults to GET /
        server.createContext("/", exchange -> {
            String response = "root";
            exchange.sendResponseHeaders(200, response.length());
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(response.getBytes());
            }
        });

        // 2. Lambda branching on getRequestMethod() -> GET + POST /users
        server.createContext("/users", exchange -> {
            if (exchange.getRequestMethod().equals("GET")) {
                listUsers(exchange);
            } else if (exchange.getRequestMethod().equals("POST")) {
                byte[] body = exchange.getRequestBody().readAllBytes();
                createUser(body);
            }
        });

        // 3. Lambda reading a request header -> GET /profile
        server.createContext("/profile", exchange -> {
            String trace = exchange.getRequestHeaders().getFirst("X-Trace-Id");
            exchange.sendResponseHeaders(200, 0);
        });

        // 4. Named HttpHandler instance resolved in the same file
        server.createContext("/upload", new UploadHandler());

        // 5. Anonymous HttpHandler -> PUT /settings with header + body
        server.createContext("/settings", new HttpHandler() {
            @Override
            public void handle(HttpExchange exchange) throws IOException {
                if ("PUT".equals(exchange.getRequestMethod())) {
                    String mode = exchange.getRequestHeaders().getFirst("X-Mode");
                    exchange.getRequestBody().readAllBytes();
                }
                exchange.sendResponseHeaders(204, -1);
            }
        });

        // 6. Method reference handler -> GET /health
        server.createContext("/health", Application::health);

        // 7. Path from a String constant + switch on the method variable
        server.createContext(API_BASE, exchange -> {
            String method = exchange.getRequestMethod();
            switch (method) {
                case "GET":
                    break;
                case "DELETE":
                    break;
                default:
                    break;
            }
        });

        // 8. Single-argument createContext (handler set later) -> GET /status
        server.createContext("/status");

        server.setExecutor(null);
        server.start();
    }

    static void listUsers(HttpExchange exchange) {
    }

    static void createUser(byte[] body) {
    }

    static void health(HttpExchange exchange) throws IOException {
        exchange.sendResponseHeaders(200, 0);
    }

    static class UploadHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            if (exchange.getRequestMethod().equals("POST")) {
                exchange.getRequestBody().readAllBytes();
            }
            exchange.sendResponseHeaders(200, 0);
        }
    }
}
