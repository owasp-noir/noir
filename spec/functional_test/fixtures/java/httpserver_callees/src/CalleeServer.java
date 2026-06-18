package com.example;

import com.sun.net.httpserver.HttpServer;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpExchange;
import java.io.IOException;
import java.net.InetSocketAddress;

public class CalleeServer {

    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(8000), 0);

        // Lambda handler -> 1-hop callee in its body.
        server.createContext("/users", exchange -> {
            listUsers(exchange);
        });

        // Named handler -> callee inside handle().
        server.createContext("/upload", new UploadHandler());

        // Method reference -> callee inside the referenced method.
        server.createContext("/health", CalleeServer::health);

        server.start();
    }

    static void listUsers(HttpExchange exchange) {
    }

    static void health(HttpExchange exchange) throws IOException {
        renderHealth(exchange);
    }

    static void renderHealth(HttpExchange exchange) {
    }

    static class UploadHandler implements HttpHandler {
        @Override
        public void handle(HttpExchange exchange) throws IOException {
            storeUpload(exchange);
        }
    }

    static void storeUpload(HttpExchange exchange) {
    }
}
