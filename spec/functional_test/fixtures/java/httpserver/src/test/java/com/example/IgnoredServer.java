package com.example;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;

// Lives under src/test/ — JavaEngine.test_path? must keep this route
// out of the analyzed surface.
public class IgnoredServer {
    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(9000), 0);
        server.createContext("/should-not-appear", exchange -> {
            exchange.sendResponseHeaders(200, 0);
        });
        server.start();
    }
}
