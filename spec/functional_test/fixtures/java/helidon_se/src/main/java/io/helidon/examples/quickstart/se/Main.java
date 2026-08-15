package io.helidon.examples.quickstart.se;

import io.helidon.webserver.WebServer;
import io.helidon.webserver.http.HttpRouting;

public final class Main {

    private Main() {
    }

    public static void main(String[] args) {
        WebServer server = WebServer.builder()
                .routing(Main::routing)
                .build()
                .start();

        System.out.println("WEB server is up! http://localhost:" + server.port());
    }

    static void routing(HttpRouting.Builder routing) {
        routing.get("/health", (req, res) -> res.send("OK"))
               .any("/ping", (req, res) -> res.send("pong"))
               .register("/greet", new GreetService());
    }
}
