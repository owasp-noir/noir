package com.example;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;

public class SwitchServer {
    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(8000), 0);

        // Colon-form switch on the method variable, alongside an UNRELATED
        // switch on a header value whose case labels are verb words. Only the
        // method switch's labels (GET, POST) may surface — DELETE/PUT here are
        // an action enum, not HTTP verbs.
        server.createContext("/actions", exchange -> {
            String method = exchange.getRequestMethod();
            switch (method) {
                case "GET":
                    break;
                case "POST":
                    break;
                default:
                    break;
            }
            String op = exchange.getRequestHeaders().getFirst("X-Op");
            switch (op) {
                case "DELETE":
                    break;
                case "PUT":
                    break;
            }
        });

        // Arrow-form (Java 14+) switch on a chained method selector.
        server.createContext("/feed", exchange -> {
            switch (exchange.getRequestMethod().toUpperCase()) {
                case "GET" -> render();
                case "HEAD" -> head();
            }
        });

        server.start();
    }

    static void render() {
    }

    static void head() {
    }
}
