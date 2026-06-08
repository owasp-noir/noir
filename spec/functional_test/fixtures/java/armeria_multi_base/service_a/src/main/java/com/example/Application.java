package com.example;

import com.linecorp.armeria.server.Server;

public class Application {
    public Server server() {
        return Server.builder()
            .annotatedService("/a", new ItemsService())
            .build();
    }
}
